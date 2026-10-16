#!/usr/bin/env python3
"""Generate original combat SFX (sword swing whoosh, hit sting). Usage: gen_combat.py OUT_DIR"""
import numpy as np, wave, sys
SR=22050
def save(p,x):
    x=x/np.sqrt(np.mean(x**2))*0.1; x*=min(1,0.95/np.max(np.abs(x)))
    f=int(0.004*SR); x[-f:]*=np.linspace(1,0,f)
    w=wave.open(p,'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x*32767).astype('<i2').tobytes()); w.close()
r=np.random.default_rng(7)
# whoosh: noise through a sweeping resonant band, swelling then fading
n=int(0.24*SR); t=np.arange(n)/SR; X=r.normal(0,1,n); y=np.zeros(n); a=b=0.0
fc=600+2400*np.sin(np.pi*t/t[-1])**2; q=0.12
for i in range(n):
    g=2*np.sin(np.pi*fc[i]/SR); a+=g*b; hp=X[i]-a-q*b; b+=g*hp; y[i]=b
save(f"{sys.argv[1]}/sword_swing_03.wav", y*np.sin(np.pi*t/t[-1])**1.5)
# sting: two quick bright notes (E6 -> B6) with short decay
n=int(0.3*SR); t=np.arange(n)/SR; s=np.zeros(n)
for st,f in [(0,1318.5),(0.07,1975.5)]:
    m=t>=st; tt=t[m]-st
    s[m]+=(np.sin(2*np.pi*f*tt)+0.3*np.sin(4*np.pi*f*tt))*np.exp(-tt/0.07)*np.minimum(tt/0.002,1)
save(f"{sys.argv[1]}/hit_sting_01.wav", s)
