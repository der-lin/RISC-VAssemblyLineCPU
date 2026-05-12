#!/usr/bin/env python3
"""
Small RV32I assembler for login_queue_app.asm.
Supports labels, comments, and a few pseudos used in this project:
  li, mv, j, ret, nop
Outputs .txt raw hex and .coe for Vivado memory initialization.
This is intentionally minimal, but it checks immediates/ranges.
"""
import re, sys, pathlib

REG = {f"x{i}": i for i in range(32)}
# optional ABI aliases
REG.update({
    'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,
    't0':5,'t1':6,'t2':7,'s0':8,'fp':8,'s1':9,
    'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
    's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,'s8':24,'s9':25,'s10':26,'s11':27,
    't3':28,'t4':29,'t5':30,'t6':31,
})
R_FUNCTS = {
    'add': (0x00,0x0,0x33), 'sub': (0x20,0x0,0x33),
    'sll': (0x00,0x1,0x33), 'slt': (0x00,0x2,0x33), 'sltu':(0x00,0x3,0x33),
    'xor': (0x00,0x4,0x33), 'srl': (0x00,0x5,0x33), 'sra': (0x20,0x5,0x33),
    'or':  (0x00,0x6,0x33), 'and': (0x00,0x7,0x33),
}
I_FUNCTS = {
    'addi':(0x0,0x13), 'slti':(0x2,0x13), 'sltiu':(0x3,0x13),
    'xori':(0x4,0x13), 'ori':(0x6,0x13), 'andi':(0x7,0x13),
}
LOADS = {'lb':(0x0,0x03),'lh':(0x1,0x03),'lw':(0x2,0x03),'lbu':(0x4,0x03),'lhu':(0x5,0x03)}
STORES = {'sb':(0x0,0x23),'sh':(0x1,0x23),'sw':(0x2,0x23)}
BR = {'beq':0x0,'bne':0x1,'blt':0x4,'bge':0x5,'bltu':0x6,'bgeu':0x7}

def parse_int(s):
    s = s.strip()
    return int(s, 0)

def reg(s):
    s=s.strip()
    if s not in REG: raise ValueError(f"unknown register {s}")
    return REG[s]

def signed_range(v,bits):
    return -(1<<(bits-1)) <= v < (1<<(bits-1))

def u(v,bits): return v & ((1<<bits)-1)

def split_ops(s):
    return [x.strip() for x in s.replace(',', ' ').split() if x.strip()]

def memop(s):
    m = re.fullmatch(r'(-?0x[0-9a-fA-F]+|-?\d+)\(([^)]+)\)', s.strip())
    if not m: raise ValueError(f"bad memory operand {s}")
    return parse_int(m.group(1)), reg(m.group(2))

def preprocess(text):
    raw=[]
    for line in text.splitlines():
        line=line.split('#',1)[0].strip()
        if not line: continue
        raw.append(line)
    # split labels and instructions
    items=[]
    for line in raw:
        while ':' in line:
            lab, rest = line.split(':',1)
            lab=lab.strip()
            if lab: items.append(('label',lab))
            line=rest.strip()
            if not line: break
        if line: items.append(('inst',line))
    return items

def li_expand(rd, imm):
    imm &= 0xffffffff
    simm = imm if imm < 0x80000000 else imm - 0x100000000
    if signed_range(simm,12):
        return [f"addi {rd}, x0, {simm}"]
    upper = (simm + 0x800) >> 12
    lower = simm - (upper << 12)
    return [f"lui {rd}, {upper}", f"addi {rd}, {rd}, {lower}"]

def expand(items):
    out=[]
    for typ,val in items:
        if typ=='label':
            out.append((typ,val)); continue
        parts=split_ops(val)
        op=parts[0]
        if op=='li':
            rd=parts[1]; imm=parse_int(parts[2])
            for inst in li_expand(rd, imm): out.append(('inst',inst))
        elif op=='mv':
            out.append(('inst',f"addi {parts[1]}, {parts[2]}, 0"))
        elif op=='j':
            out.append(('inst',f"jal x0, {parts[1]}"))
        elif op=='ret':
            out.append(('inst',"jalr x0, x1, 0"))
        elif op=='nop':
            out.append(('inst',"addi x0, x0, 0"))
        else:
            out.append(('inst',val))
    return out

def enc_R(f7,rs2,rs1,f3,rd,opc):
    return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

def enc_I(imm,rs1,f3,rd,opc):
    if not signed_range(imm,12): raise ValueError(f"I imm out of range: {imm}")
    return (u(imm,12)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

def enc_S(imm,rs2,rs1,f3,opc):
    if not signed_range(imm,12): raise ValueError(f"S imm out of range: {imm}")
    imm=u(imm,12)
    return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1f)<<7)|opc

def enc_B(off,rs2,rs1,f3):
    if off % 2: raise ValueError(f"B offset not halfword aligned: {off}")
    if not signed_range(off,13): raise ValueError(f"B offset out of range: {off}")
    imm=u(off,13)
    return ((imm>>12)&1)<<31 | ((imm>>5)&0x3f)<<25 | (rs2<<20)|(rs1<<15)|(f3<<12) | ((imm>>1)&0xf)<<8 | ((imm>>11)&1)<<7 | 0x63

def enc_U(imm,rd,opc):
    # assembler source uses either signed upper immediate or hex upper value; store low 20 bits.
    return (u(imm,20)<<12)|(rd<<7)|opc

def enc_J(off,rd):
    if off % 2: raise ValueError(f"J offset not halfword aligned: {off}")
    if not signed_range(off,21): raise ValueError(f"J offset out of range: {off}")
    imm=u(off,21)
    return ((imm>>20)&1)<<31 | ((imm>>1)&0x3ff)<<21 | ((imm>>11)&1)<<20 | ((imm>>12)&0xff)<<12 | (rd<<7) | 0x6f

def assemble_inst(line, pc, labels):
    p=split_ops(line); op=p[0]
    if op in R_FUNCTS:
        rd,rs1,rs2=reg(p[1]),reg(p[2]),reg(p[3]); f7,f3,opc=R_FUNCTS[op]
        return enc_R(f7,rs2,rs1,f3,rd,opc)
    if op in I_FUNCTS:
        rd,rs1,imm=reg(p[1]),reg(p[2]),parse_int(p[3]); f3,opc=I_FUNCTS[op]
        return enc_I(imm,rs1,f3,rd,opc)
    if op in ('slli','srli','srai'):
        rd,rs1,sh=reg(p[1]),reg(p[2]),parse_int(p[3])
        if not (0 <= sh < 32): raise ValueError(f"bad shamt {sh}")
        f3=0x1 if op=='slli' else 0x5
        f7=0x20 if op=='srai' else 0x00
        imm=(f7<<5)|sh
        return enc_I(imm,rs1,f3,rd,0x13)
    if op in LOADS:
        rd=reg(p[1]); imm,rs1=memop(p[2]); f3,opc=LOADS[op]
        return enc_I(imm,rs1,f3,rd,opc)
    if op in STORES:
        rs2=reg(p[1]); imm,rs1=memop(p[2]); f3,opc=STORES[op]
        return enc_S(imm,rs2,rs1,f3,opc)
    if op in BR:
        rs1,rs2=reg(p[1]),reg(p[2]); lab=p[3]
        off=labels[lab]-pc
        return enc_B(off,rs2,rs1,BR[op])
    if op=='lui':
        return enc_U(parse_int(p[2]),reg(p[1]),0x37)
    if op=='auipc':
        return enc_U(parse_int(p[2]),reg(p[1]),0x17)
    if op=='jal':
        rd=reg(p[1]); target=p[2]
        off=(labels[target] if target in labels else parse_int(target))-pc
        return enc_J(off,rd)
    if op=='jalr':
        rd,rs1,imm=reg(p[1]),reg(p[2]),parse_int(p[3])
        return enc_I(imm,rs1,0x0,rd,0x67)
    raise ValueError(f"unsupported instruction: {line}")

def main():
    inp = pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else pathlib.Path('login_queue_app.asm')
    text=inp.read_text()
    items=expand(preprocess(text))
    labels={}; pc=0; insts=[]
    for typ,val in items:
        if typ=='label':
            if val in labels: raise ValueError(f"duplicate label {val}")
            labels[val]=pc
        else:
            insts.append((pc,val)); pc+=4
    words=[]
    for pc,line in insts:
        try:
            words.append(assemble_inst(line,pc,labels))
        except Exception as e:
            raise SystemExit(f"Error at PC 0x{pc:08x}: {line}\n{e}")
    txt=inp.with_suffix('.txt')
    coe=inp.with_suffix('.coe')
    txt.write_text('\n'.join(f'{w:08x}' for w in words)+'\n')
    coe.write_text('memory_initialization_radix=16;\nmemory_initialization_vector=\n' + ',\n'.join(f'{w:08x}' for w in words) + ';\n')
    print(f"assembled {len(words)} instructions")
    print(f"wrote {txt}")
    print(f"wrote {coe}")
    if len(words)>256:
        print("WARNING: program exceeds 256 instructions; increase imem depth/address width.")

if __name__=='__main__': main()
