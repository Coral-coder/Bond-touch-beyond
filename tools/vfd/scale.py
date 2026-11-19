"""Scale2x (EPX) and Scale3x (AdvMAME3x) on 0/1 bitmaps."""
def px(b, x, y):
    if 0 <= y < len(b) and 0 <= x < len(b[0]): return b[y][x]
    return 0

def scale2x(b):
    h, w = len(b), len(b[0]); o = [[0]*(w*2) for _ in range(h*2)]
    for y in range(h):
        for x in range(w):
            P = b[y][x]; A = px(b,x,y-1); B = px(b,x+1,y); C = px(b,x-1,y); D = px(b,x,y+1)
            e0 = A if (C == A and C != D and A != B) else P
            e1 = B if (A == B and A != C and B != D) else P
            e2 = C if (D == C and D != B and C != A) else P
            e3 = D if (B == D and B != A and D != C) else P
            o[2*y][2*x], o[2*y][2*x+1], o[2*y+1][2*x], o[2*y+1][2*x+1] = e0, e1, e2, e3
    return o

def scale3x(b):
    h, w = len(b), len(b[0]); o = [[0]*(w*3) for _ in range(h*3)]
    for y in range(h):
        for x in range(w):
            A=px(b,x-1,y-1); B=px(b,x,y-1); C=px(b,x+1,y-1)
            D=px(b,x-1,y);   E=b[y][x];     F=px(b,x+1,y)
            G=px(b,x-1,y+1); H=px(b,x,y+1); I=px(b,x+1,y+1)
            if B != H and D != F:
                e0 = D if D == B else E
                e1 = B if (D == B and E != C) or (B == F and E != A) else E
                e2 = F if B == F else E
                e3 = D if (D == B and E != G) or (D == H and E != A) else E
                e4 = E
                e5 = F if (B == F and E != I) or (H == F and E != C) else E
                e6 = D if D == H else E
                e7 = H if (D == H and E != I) or (H == F and E != G) else E
                e8 = F if H == F else E
            else:
                e0=e1=e2=e3=e4=e5=e6=e7=e8=E
            for i, v in enumerate((e0,e1,e2,e3,e4,e5,e6,e7,e8)):
                o[3*y + i//3][3*x + i%3] = v
    return o
