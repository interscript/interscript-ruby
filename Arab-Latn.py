#!/usr/bin/python
# -*- coding: iso-8859-15 -*-

# This program written in Python is offered as an example of converting Arabic characters (in Unicode) to the MRZ format.
# The Arabic characters are contained in a file “Arabic source.txt” and the corresponding MRZ data is written to a file “MRZ output.txt”.

import unicodedata
import encodings.utf_8_sig
import codecs

# TRANSLITERATE
def Arabic_to_MRZ(unicode_string):
    transform = { 0x20: '<', 0x21: 'XE', 0x22: 'XAA', 0x23: 'XAE', 0x24: 'U',
        0x25: 'I', 0x26: 'XI', 0x27: 'A', 0x28: 'B', 0x29: 'XAH',
        0x2A: 'T', 0x2B: 'XTH', 0x2C: 'J', 0x2D: 'XH', 0x2E: 'XKH',
        0x2F: 'D', 0x30: 'XDH', 0x31: 'R', 0x32: 'Z', 0x33: 'S',
        0x34: 'XSH', 0x35: 'XSS', 0x36: 'XDZ', 0x37: 'XTT', 0x38: 'XZZ',
        0x39: 'E', 0x3A: 'G', 0x41: 'F', 0x42: 'Q', 0x43: 'K', 0x44: 'L',
        0x45: 'M', 0x46: 'N', 0x47: 'H', 0x48: 'W', 0x49: 'XAY',
        0x4A: 'Y', 0x71: 'XXA', 0x79: 'XXT', 0x7E: 'P', 0x7C: 'XRT',
        0x81: 'XKE', 0x85: 'XXH', 0x86: 'XC', 0x88: 'XXD', 0x89: 'XDR',
        0x91: 'XXR', 0x93: 'XRR', 0x96: 'XRX', 0x98: 'XJ', 0x9A: 'XXS',
        0xA4: 'XV', 0xA5: 'XF', 0xA9: 'XKK', 0xAB: 'XXK', 0xAD: 'XNG',
        0xAF: 'XGG', 0xBA: 'XNN', 0xBC: 'XXN', 0xBE: 'XDO', 0xC0: 'XYH',
        0xC1: 'XXG', 0xC2: 'XGE', 0xC3: 'XTG',
        0xCC: 'XYA', 0xCD: 'XXY', 0xD0: 'Y', 0xD2: 'XYB', 0xD3: 'XBE'}

    name_in = unicode_string
    name_out = ""
    for c in name_in:
# check for shadda (double)
        if ord(c) == 0x51:
            name_out = name_out + char
        else:
            if ord(c) in transform:
                char = transform[ord(c)]
                name_out = name_out + char
            print name_out
            return name_out

#
# MAIN - Arabic to MRZ
#

# open input and output files
fin = encodings.utf_8_sig.codecs.open('arabic-source.txt', 'r') #b', 'utf-8-sig', 'ignore', 1)
fout = open('mrz-output.txt', 'w')

# loop through the input file
try:
    for arabic_name in fin:
        MRZ_name = Arabic_to_MRZ(arabic_name)
        fout.write(MRZ_name)
        fout.write('\n')
finally:
    fin.close()
fout.flush()
fout.close()

