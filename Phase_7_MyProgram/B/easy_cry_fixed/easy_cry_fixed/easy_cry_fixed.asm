# ================================================================
# easy_cry_fixed.asm
# ------------------------------------------------
# Application : fixed-input Feistel toy encryption/decryption test
# Target CPU  : user's RV32I pipeline CPU on FPGA
# IO mapping  : seg7 output = 0xffff000c
# Display     : 600D600D if encryption/decryption check passes
#               BAD0BAD0 if either check fails
#
# Fixed test vectors:
#   plaintext        = 0x12345678
#   master key       = 0x00002B7E
#   expected cipher  = 0x36C8930C
#
# Feistel round:
#   F(R,K) = ((R xor K) + ((R << 3) xor (R >> 2))) & 0xFFFF
#   Enc round: L' = R, R' = L xor F(R,K)
#   Dec round: oldL = R' xor F(L',K), oldR = L'
# ================================================================

# Register convention:
# x1  return address
# x2  switch IO base, unused here but initialized for consistency
# x3  seg7 IO base 0xffff000c
# x10 general display/result
# x11 plaintext / master key temp
# x20 L half, x21 R half, x22 current round key
# x24..x27 round keys K0..K3
# x30 0x0000FFFF mask for 16-bit values

start:
    # IO base addresses
    lui   x2, 0xffff0             # x2 = 0xffff0000
    addi  x3, x2, 12              # x3 = 0xffff000c, seg7 output
    addi  x2, x2, 4               # x2 = 0xffff0004, switch input

    # Common 16-bit mask
    li    x30, 0x0000ffff

    # Store fixed test vectors in data RAM for board-side observation.
    li    x10, 0x12345678
    sw    x10, 0x180(x0)          # mem[0x180] = plaintext
    li    x11, 0x00002b7e
    sw    x11, 0x184(x0)          # mem[0x184] = master key
    li    x12, 0x36c8930c
    sw    x12, 0x188(x0)          # mem[0x188] = expected ciphertext

    # Show start marker briefly: FE15FE15 means Feistel start.
    li    x10, 0xfe15fe15
    jal   x1, show_delay

    # Derive round keys from master key x11.
    jal   x1, derive_keys

    # Encrypt plaintext.
    lw    x10, 0x180(x0)
    jal   x1, encrypt32           # x10 = computed ciphertext
    sw    x10, 0x18c(x0)          # mem[0x18C] = computed ciphertext

    # Check ciphertext against expected ciphertext.
    lw    x12, 0x188(x0)
    bne   x10, x12, fail

    # Decrypt computed ciphertext.
    jal   x1, decrypt32           # x10 = decrypted plaintext
    sw    x10, 0x190(x0)          # mem[0x190] = decrypted plaintext

    # Check decrypted plaintext against original plaintext.
    lw    x12, 0x180(x0)
    bne   x10, x12, fail

pass:
    li    x10, 0x600d600d
    sw    x10, 0x194(x0)          # mem[0x194] = PASS flag
    jal   x1, show
pass_loop:
    jal   x0, pass_loop

fail:
    li    x10, 0xbad0bad0
    sw    x10, 0x194(x0)          # mem[0x194] = FAIL flag
    jal   x1, show
fail_loop:
    jal   x0, fail_loop

# ================================================================
# Subroutines
# ================================================================

# show: write x10 to the 8-digit seven-segment display.
show:
    sw    x10, 0(x3)
    jalr  x0, x1, 0

# show_delay: display x10, then hold for a visible delay.
show_delay:
    sw    x10, 0(x3)
    li    x5, 600
show_delay_outer:
    li    x6, 700
show_delay_inner:
    addi  x6, x6, -1
    bne   x6, x0, show_delay_inner
    addi  x5, x5, -1
    bne   x5, x0, show_delay_outer
    jalr  x0, x1, 0

# derive_keys:
# Input : x11 = 16-bit master key
# Output: x24=K0, x25=K1, x26=K2, x27=K3
#   K0 = key
#   K1 = ((key << 3) xor 0x1357) & 0xFFFF
#   K2 = ((key >> 1) xor 0x2468) & 0xFFFF
#   K3 = ((key << 5) xor (key >> 3) xor 0x55AA) & 0xFFFF
# Also stores K0..K3 to mem[0x198..0x1A4].
derive_keys:
    and   x24, x11, x30           # K0

    slli  x5, x11, 3
    li    x6, 0x1357
    xor   x25, x5, x6
    and   x25, x25, x30           # K1

    srli  x5, x11, 1
    li    x6, 0x2468
    xor   x26, x5, x6
    and   x26, x26, x30           # K2

    slli  x5, x11, 5
    srli  x6, x11, 3
    xor   x5, x5, x6
    li    x6, 0x55aa
    xor   x27, x5, x6
    and   x27, x27, x30           # K3

    sw    x24, 0x198(x0)
    sw    x25, 0x19c(x0)
    sw    x26, 0x1a0(x0)
    sw    x27, 0x1a4(x0)
    jalr  x0, x1, 0

# encrypt32:
# Input : x10 = 32-bit plaintext
# Output: x10 = 32-bit ciphertext
# Uses x20=L, x21=R.
encrypt32:
    add   x31, x1, x0            # save caller return address
    srli  x20, x10, 16            # L = upper 16 bits
    and   x21, x10, x30           # R = lower 16 bits

    add   x22, x24, x0            # K0
    jal   x1, enc_round
    add   x22, x25, x0            # K1
    jal   x1, enc_round
    add   x22, x26, x0            # K2
    jal   x1, enc_round
    add   x22, x27, x0            # K3
    jal   x1, enc_round

    slli  x10, x20, 16
    or    x10, x10, x21
    jalr  x0, x31, 0             # return to caller

# decrypt32:
# Input : x10 = 32-bit ciphertext
# Output: x10 = 32-bit plaintext
# Uses reverse key order K3,K2,K1,K0.
decrypt32:
    add   x31, x1, x0            # save caller return address
    srli  x20, x10, 16            # L_next
    and   x21, x10, x30           # R_next

    add   x22, x27, x0            # K3
    jal   x1, dec_round
    add   x22, x26, x0            # K2
    jal   x1, dec_round
    add   x22, x25, x0            # K1
    jal   x1, dec_round
    add   x22, x24, x0            # K0
    jal   x1, dec_round

    slli  x10, x20, 16
    or    x10, x10, x21
    jalr  x0, x31, 0             # return to caller

# enc_round:
# Input : x20=L, x21=R, x22=K
# Output: x20=R, x21=L xor F(R,K)
enc_round:
    xor   x5, x21, x22            # t0 = R xor K
    slli  x6, x21, 3              # t1 = R << 3
    srli  x7, x21, 2              # t2 = R >> 2
    xor   x6, x6, x7              # t1 = (R << 3) xor (R >> 2)
    add   x5, x5, x6              # F before masking, addition adds nonlinearity
    and   x5, x5, x30             # F = F & 0xFFFF
    add   x7, x21, x0             # save old R
    xor   x21, x20, x5            # newR = oldL xor F
    and   x21, x21, x30
    add   x20, x7, x0             # newL = oldR
    jalr  x0, x1, 0

# dec_round:
# Input : x20=L_next, x21=R_next, x22=K
# Output: x20=oldL, x21=oldR
# oldR = L_next; oldL = R_next xor F(L_next,K)
dec_round:
    xor   x5, x20, x22            # t0 = L_next xor K
    slli  x6, x20, 3
    srli  x7, x20, 2
    xor   x6, x6, x7
    add   x5, x5, x6
    and   x5, x5, x30             # F(L_next,K)
    xor   x7, x21, x5             # oldL = R_next xor F
    and   x7, x7, x30
    add   x21, x20, x0            # oldR = L_next
    add   x20, x7, x0             # oldL
    jalr  x0, x1, 0
