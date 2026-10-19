// Minimal LZ4 block decompressor (raw blocks produced by lz4.block.compress(store_size=False)).
#include "engine.h"
#include <string.h>

int lz4_decompress(const u8 *src, int srcLen, u8 *dst, int dstCap) {
    const u8 *ip = src, *iend = src + srcLen;
    u8 *op = dst, *oend = dst + dstCap;
    while (ip < iend) {
        u8 token = *ip++;
        int lit = token >> 4;
        if (lit == 15) {
            u8 b;
            do { if (ip >= iend) return -1; b = *ip++; lit += b; } while (b == 255);
        }
        if (ip + lit > iend || op + lit > oend) return -1;
        memcpy(op, ip, lit);
        ip += lit;
        op += lit;
        if (ip >= iend) break;  // last sequence has literals only
        if (ip + 2 > iend) return -1;
        int off = ip[0] | (ip[1] << 8);
        ip += 2;
        int len = token & 15;
        if (len == 15) {
            u8 b;
            do { if (ip >= iend) return -1; b = *ip++; len += b; } while (b == 255);
        }
        len += 4;
        u8 *match = op - off;
        if (off == 0 || match < dst || op + len > oend) return -1;
        while (len--) *op++ = *match++;  // byte copy handles overlapping matches
    }
    return (int)(op - dst);
}
