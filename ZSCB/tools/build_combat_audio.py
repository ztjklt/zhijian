"""Rebuild small mono WAV banks from the credited CC0 source takes + original synthesis.
Requires ffmpeg and numpy. No network access, credentials or user files.
"""
from pathlib import Path
import subprocess, wave, json, hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/audio/combat';SRC=OUT/'sources';RATE=44100
rng=np.random.default_rng(20261025)
manifest=[]
def read(name,speed=1.0):
    path=SRC/name
    raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(path),'-f','f32le','-ar',str(RATE),'-ac','1','-'])
    x=np.frombuffer(raw,dtype='<f4').astype(float)
    active=np.flatnonzero(abs(x)>max(.003,abs(x).max()*.025))
    if len(active):x=x[max(0,active[0]-220):min(len(x),active[-1]+800)]
    if speed!=1:x=np.interp(np.arange(0,len(x),speed),np.arange(len(x)),x)
    x=x[:int(RATE*2.3)]
    return x/max(.01,abs(x).max())
def mix(*layers):
    result=np.zeros(max(len(x) for x in layers))
    for x in layers:result[:len(x)]+=x
    return result

def synth(kind,variant):
    duration=.30 if kind=='bow' else .46 if kind=='gun' else .36
    t=np.arange(int(RATE*duration))/RATE
    noise=rng.normal(0,1,len(t));smooth=np.convolve(noise,np.ones(9)/9,'same')
    if kind=='bow':
        f=170+variant*23
        return sum(np.sin(2*np.pi*f*k*t)*np.exp(-t*(16+k*3))/k for k in range(1,8))*.3+noise*np.exp(-t*85)*.17
    if kind=='gun':
        return noise*np.exp(-t*30)*.7+smooth*np.exp(-t*10)*.6+np.sin(2*np.pi*(100*t-38*t*t))*np.exp(-t*14)*.6
    if kind=='hammer':return np.sin(2*np.pi*(95*t-40*t*t))*np.exp(-t*15)+smooth*np.exp(-t*20)*.7
    if kind=='air':return smooth*np.sin(np.pi*np.minimum(t/duration,1))**2*np.exp(-t*3)*1.5
    return noise*np.exp(-t*70)*.2

def save(key,v,x,sources):
    x=np.asarray(x,float);x-=x.mean()
    fade=min(int(RATE*.008),len(x)//6);tail=min(int(RATE*.045),len(x)//5)
    x[:fade]*=np.linspace(0,1,fade);x[-tail:]*=np.linspace(1,0,tail)
    # Fixed peak headroom, soft crest compression; runtime applies mix/distance gains.
    x=np.tanh(x*1.2);x*=.80/max(.001,abs(x).max())
    pcm=(x*32767).astype('<i2');name=f'{key}_{v}.wav'
    with wave.open(str(OUT/name),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(pcm.tobytes())
    manifest.append({'file':name,'sources':sources,'seconds':round(len(x)/RATE,4),'sha256':hashlib.sha256((OUT/name).read_bytes()).hexdigest()})

for v in range(1,4):
    blade=f'sword_sword.{[1,3,5][v-1]}.ogg';clash=f'sword_sword_clash.{v}.ogg'
    wood=f'rpg_wood_0{v}.ogg';stone=f'rpg_stones_0{v}.ogg';spear=f'rpg_blade_0{v}.ogg'
    save('sword_swing',v,mix(read(blade)*.7,synth('air',v)*.4),[blade,'original air synthesis'])
    save('sword_hit',v,mix(read(clash)*.8,synth('hammer',v)*.16),[clash,'original low impact synthesis'])
    save('hammer_swing',v,mix(synth('air',v)*1.4,read(wood,.8)*.15),[wood,'original broad air synthesis'])
    save('hammer_hit',v,mix(read(stone,.72)*.6,read(wood,.8)*.6,synth('hammer',v)),[stone,wood,'original low impact synthesis'])
    save('spear_swing',v,mix(read(blade,1.3)*.3,synth('air',v)*.6),[blade,'original narrow air synthesis'])
    save('spear_hit',v,mix(read(spear,1.15)*.8,read(wood,1.2)*.25),[spear,wood])
    t=np.arange(int(RATE*.44))/RATE
    draw=np.sin(2*np.pi*(280*t+320*t*t))*.12+np.sin(2*np.pi*93*t)*.1+rng.normal(0,.1,len(t))
    draw*=np.sin(np.pi*t/.44)**2
    save('bow_draw',v,draw,['original taut string synthesis'])
    save('bow_shoot',v,mix(synth('bow',v),synth('air',v)*.25),['original plucked string + arrow air synthesis'])
    save('bow_hit',v,mix(read(wood,1.25)*.8,synth('bow',v)*.18),[wood,'original string synthesis'])
    save('firearm_shoot',v,synth('gun',v),['original powder crack/noise + resonant boom synthesis'])
    save('firearm_hit',v,mix(read(stone,1.45)*.5,synth('hammer',v)*.5,synth('gun',v)*.28),[stone,'original impact/noise synthesis'])
    male=['human_3yell1.wav','human_3yell3.wav','human_2yell4.wav'][v-1]
    save('death_human_low',v,read(male),[male])
    save('death_human_high',v,read('female_original0.ogg',[1.0,.96,1.04][v-1]),['female_original0.ogg (processed variants of one take)'])
    save('death_horse',v,read(f'horse_{v}.mp3'),[f'horse_{v}.mp3'])
    small=f'creature_scream_0{1 if v%2 else 2}.ogg'
    save('death_rabbit',v,read(small,1.65+v*.06),[small+' (stylized small-animal processing)'])
    deer=f'creature_hurt_0{v}.ogg'
    save('death_deer',v,read(deer,1.15+v*.04),[deer+' (stylized animal processing)'])
    bat=f'creature_bug_0{v}.ogg'
    save('death_bat',v,read(bat,1.4),[bat+' (stylized bat processing)'])
    dragon=f'creature_roar_0{v}.ogg'
    save('death_dragon',v,read(dragon,.72),[dragon+' (pitched down)'])
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('COMBAT AUDIO:',len(manifest),'WAVs;',round(sum((OUT/m['file']).stat().st_size for m in manifest)/1048576,2),'MiB')
