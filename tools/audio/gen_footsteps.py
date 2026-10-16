#!/usr/bin/env python3
"""Generate terrain footstep SFX (sand, grass, swamp) as procedural filtered noise. Usage: gen_footsteps.py OUT_DIR"""
import numpy as np, wave, sys
SR=22050
def band(x,lo,hi):
    X=np.fft.rfft(x); f=np.fft.rfftfreq(len(x),1/SR)
    X[(f<lo)|(f>hi)]=0; return np.fft.irfft(X,len(x))
def env(n,a,d):
    t=np.arange(n)/SR; return np.minimum(t/a,1)*np.exp(-t/d)
def save(p,x):
    x=x/np.sqrt(np.mean(x**2))*0.1; x*=min(1,0.95/np.max(np.abs(x)))
    f=int(0.004*SR); x[-f:]*=np.linspace(1,0,f)
    w=wave.open(p,'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x*32767).astype('<i2').tobytes()); w.close()
def sand(r):
    n=int(0.22*SR); x=np.zeros(n)
    for _ in range(r.integers(25,40)):  # granular crunch
        s=r.integers(0,int(0.12*SR)); L=r.integers(40,200)
        g=r.normal(0,1,L)*np.exp(-np.arange(L)/(L/4))*r.uniform(.3,1)
        x[s:s+L]+=g[:n-s]
    x=band(x,1500,9000)*env(n,0.004,0.06)+band(r.normal(0,.3,n),300,2500)*env(n,0.003,0.03)
    return x
def grass(r):
    n=int(0.28*SR)
    x=band(r.normal(0,1,n),2500,7000)*env(n,0.02,0.07)*(1+0.5*np.sin(2*np.pi*r.uniform(25,40)*np.arange(n)/SR))
    x+=band(r.normal(0,1,n),120,500)*env(n,0.005,0.03)*0.8
    return x
def swamp(r):
    n=int(0.34*SR); t=np.arange(n)/SR
    x=band(r.normal(0,1,n),80,900)*env(n,0.01,0.08)
    f0=r.uniform(180,260); f=f0+r.uniform(250,400)*(t/t[-1])  # rising bubble pop
    x+=np.sin(2*np.pi*np.cumsum(f)/SR)*env(n,0.03,0.05)*0.6
    x+=band(r.normal(0,1,n),1500,4000)*env(n,0.06,0.05)*0.25  # wet slap tail
    return x
for name,fn in [('sand',sand),('grass',grass),('swamp',swamp)]:
    for i in range(1,4):
        save(f"{sys.argv[1]}/footstep_{name}_{i:02d}.wav",fn(np.random.default_rng({"sand":100,"grass":200,"swamp":300}[name]+i)))
