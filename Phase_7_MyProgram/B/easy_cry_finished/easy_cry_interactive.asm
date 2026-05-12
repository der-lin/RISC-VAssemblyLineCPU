# ================================================================
# easy_cry_interactive.asm
# ------------------------------------------------
# Application : interactive Feistel toy encryption/decryption
# Target CPU  : user's RV32I pipeline CPU on FPGA
# IO mapping  : switch input = 0xffff0004
#               seg7 output  = 0xffff000c
# Display     : use SW[5:0] = 000000 to display CPU application output.
#
# Interaction:
#   SW14 = mode selector at reset/start
#          0 -> encryption mode: input plaintext, input key, output ciphertext
#          1 -> decryption mode: input ciphertext, input key, output plaintext
#   SW13 = confirm one hex digit; after each confirmation, return SW13 to 0
#   SW[9:6] = current hex digit 0..F
#
# Input lengths:
#   plaintext/ciphertext: 8 hex digits, displayed as current accumulator
#   key                 : 4 hex digits, displayed as A000xxxx
#
# Feistel round:
#   F(R,K) = ((R xor K) + ((R << 3) xor (R >> 2))) & 0xFFFF
# ================================================================

# Register convention:
# x1  return address
# x2  switch IO base 0xffff0004
# x3  seg7 IO base   0xffff000c
# x10 display/result/return flag
# x11 input accumulator / master key temp
# x20 L half, x21 R half, x22 current round key
# x24..x27 round keys K0..K3
# x30 0x0000FFFF mask

start:
    lui   x2, 0xffff0             # x2 = 0xffff0000
    addi  x3, x2, 12              # x3 = 0xffff000c, seg7 output
    addi  x2, x2, 4               # x2 = 0xffff0004, switch input
    li    x30, 0x0000ffff

    # Read mode once at startup/reset.
    # SW14=0: encrypt; SW14=1: decrypt.
    lw    x5, 0(x2)
    srli  x6, x5, 14
    andi  x6, x6, 1
    bne   x6, x0, decrypt_mode

# ------------------------------------------------
# Encryption mode
# ------------------------------------------------
encrypt_mode:
    li    x10, 0xe0000000         # E means encryption mode
    jal   x1, show_delay

    # Input 8 hex digits as plaintext.
    li    x13, 8
    li    x14, 0x00000000
    jal   x1, input_hex_n         # x11 = plaintext
    sw    x11, 0x180(x0)          # mem[0x180] = plaintext

    # Input 4 hex digits as master key.
    li    x10, 0xa0000000         # A means key input phase
    jal   x1, show_delay
    li    x13, 4
    li    x14, 0xa0000000
    jal   x1, input_hex_n         # x11 = key
    sw    x11, 0x184(x0)          # mem[0x184] = master key

    jal   x1, derive_keys
    lw    x10, 0x180(x0)
    jal   x1, encrypt32           # x10 = ciphertext
    sw    x10, 0x188(x0)          # mem[0x188] = ciphertext
    sw    x10, 0x194(x0)          # mem[0x194] = final result
    jal   x1, show
encrypt_result_loop:
    jal   x0, encrypt_result_loop

# ------------------------------------------------
# Decryption mode
# ------------------------------------------------
decrypt_mode:
    li    x10, 0xd0000000         # D means decryption mode
    jal   x1, show_delay

    # Input 8 hex digits as ciphertext.
    li    x13, 8
    li    x14, 0x00000000
    jal   x1, input_hex_n         # x11 = ciphertext
    sw    x11, 0x18c(x0)          # mem[0x18C] = ciphertext

    # Input 4 hex digits as master key.
    li    x10, 0xa0000000         # A means key input phase
    jal   x1, show_delay
    li    x13, 4
    li    x14, 0xa0000000
    jal   x1, input_hex_n         # x11 = key
    sw    x11, 0x184(x0)          # mem[0x184] = master key

    jal   x1, derive_keys
    lw    x10, 0x18c(x0)
    jal   x1, decrypt32           # x10 = plaintext
    sw    x10, 0x190(x0)          # mem[0x190] = plaintext
    sw    x10, 0x194(x0)          # mem[0x194] = final result
    jal   x1, show
decrypt_result_loop:
    jal   x0, decrypt_result_loop

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
    li    x5, 450
show_delay_outer:
    li    x6, 600
show_delay_inner:
    addi  x6, x6, -1
    bne   x6, x0, show_delay_inner
    addi  x5, x5, -1
    bne   x5, x0, show_delay_outer
    jalr  x0, x1, 0

# input_hex_n:
#   x13 = number of hex digits to input
#   x14 = display prefix. Use 0 for full 8-digit value input;
#         use 0xA0000000 for 4-digit key input.
# Return:
#   x11 = accumulated input value
# It samples digit from SW[9:6], and confirms one digit on SW13 rising edge.
input_hex_n:
    addi  x11, x0, 0              # accumulator
    addi  x12, x0, 0              # digit counter
    add   x10, x14, x0
    sw    x10, 0(x3)              # show initial prefix / zero accumulator
input_wait_press:
    lw    x5, 0(x2)
    srli  x6, x5, 13              # wait SW13 press
    andi  x6, x6, 1
    beq   x6, x0, input_wait_press

    srli  x7, x5, 6               # digit = SW[9:6]
    andi  x7, x7, 15
    slli  x11, x11, 4
    or    x11, x11, x7
    or    x10, x14, x11           # display input progress
    sw    x10, 0(x3)

input_wait_release:
    lw    x5, 0(x2)
    srli  x6, x5, 13
    andi  x6, x6, 1
    bne   x6, x0, input_wait_release

    addi  x12, x12, 1
    bne   x12, x13, input_wait_press
    jalr  x0, x1, 0

# derive_keys:
# Input : x11 = 16-bit master key
# Output: x24=K0, x25=K1, x26=K2, x27=K3
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
encrypt32:
    add   x31, x1, x0            # save caller return address
    srli  x20, x10, 16
    and   x21, x10, x30

    add   x22, x24, x0
    jal   x1, enc_round
    add   x22, x25, x0
    jal   x1, enc_round
    add   x22, x26, x0
    jal   x1, enc_round
    add   x22, x27, x0
    jal   x1, enc_round

    slli  x10, x20, 16
    or    x10, x10, x21
    jalr  x0, x31, 0             # return to caller

# decrypt32:
# Input : x10 = 32-bit ciphertext
# Output: x10 = 32-bit plaintext
decrypt32:
    add   x31, x1, x0            # save caller return address
    srli  x20, x10, 16
    and   x21, x10, x30

    add   x22, x27, x0
    jal   x1, dec_round
    add   x22, x26, x0
    jal   x1, dec_round
    add   x22, x25, x0
    jal   x1, dec_round
    add   x22, x24, x0
    jal   x1, dec_round

    slli  x10, x20, 16
    or    x10, x10, x21
    jalr  x0, x31, 0             # return to caller

# enc_round:
# Input : x20=L, x21=R, x22=K
# Output: x20=R, x21=L xor F(R,K)
enc_round:
    xor   x5, x21, x22
    slli  x6, x21, 3
    srli  x7, x21, 2
    xor   x6, x6, x7
    add   x5, x5, x6
    and   x5, x5, x30
    add   x7, x21, x0
    xor   x21, x20, x5
    and   x21, x21, x30
    add   x20, x7, x0
    jalr  x0, x1, 0

# dec_round:
# Input : x20=L_next, x21=R_next, x22=K
# Output: x20=oldL, x21=oldR
dec_round:
    xor   x5, x20, x22
    slli  x6, x20, 3
    srli  x7, x20, 2
    xor   x6, x6, x7
    add   x5, x5, x6
    and   x5, x5, x30
    xor   x7, x21, x5
    and   x7, x7, x30
    add   x21, x20, x0
    add   x20, x7, x0
    jalr  x0, x1, 0
