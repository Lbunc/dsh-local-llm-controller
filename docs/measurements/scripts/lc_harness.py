import sys, json, time, random
random.seed(7)

# ---------- reference implementations (verified correct) ----------
def ref_merge_intervals(ivs):
    if not ivs: return []
    ivs=sorted(ivs,key=lambda x:(x[0],x[1]))
    out=[list(ivs[0])]
    for s,e in ivs[1:]:
        if s<=out[-1][1]: out[-1][1]=max(out[-1][1],e)
        else: out.append([s,e])
    return out

def ref_trap(h):
    if not h: return 0
    n=len(h); l=[0]*n; r=[0]*n
    l[0]=h[0]
    for i in range(1,n): l[i]=max(l[i-1],h[i])
    r[n-1]=h[n-1]
    for i in range(n-2,-1,-1): r[i]=max(r[i+1],h[i])
    return sum(min(l[i],r[i])-h[i] for i in range(n))

# ---------- test cases ----------
random.seed(7)
merge_cases=[]
# deterministic edge cases (LeetCode semantics: only overlap / contiguous merge; gap of 1 does NOT merge)
merge_cases.append(([[1,3],[2,6],[8,10],[15,18]], [[1,6],[8,10],[15,18]]))
merge_cases.append(([[1,4],[4,5]], [[1,5]]))        # contiguous [4,5] merges
merge_cases.append(([[1,4],[5,6]], [[1,4],[5,6]]))  # gap of 1 (4->5) NOT merge
merge_cases.append(([[1,4],[0,4]], [[0,4]]))
merge_cases.append(([[1,4],[0,0]], [[0,0],[1,4]]))
for _ in range(20):
    ivs=[]
    for _ in range(random.randint(1,8)):
        a=random.randint(0,40); b=random.randint(a+1,80); ivs.append([a,b])
    merge_cases.append((ivs, ref_merge_intervals(ivs)))

trap_cases=[]
for _ in range(30):
    h=[random.randint(0,20) for _ in range(random.randint(1,60))]
    trap_cases.append((h, ref_trap(h)))

# large
def make_large_merge(n):
    ivs=[]; cur=0
    for _ in range(n):
        s=random.randint(cur-3,cur+2); e=s+random.randint(1,10); cur=e; ivs.append([s,e])
    return ivs
large_merge=make_large_merge(5000)
large_merge_exp=ref_merge_intervals(large_merge)
large_trap=[random.randint(0,100) for _ in range(50000)]
large_trap_exp=ref_trap(large_trap)

# LFU reference
class RefLFU:
    def __init__(self,cap):
        self.cap=cap; self.d={}; self.freq={}; self.order={}; self.tick=0
    def _evict(self):
        if len(self.d)<self.cap: return
        # min freq, then least recently used (smallest order)
        cand=sorted(self.d, key=lambda x:(self.freq[x], self.order[x]))
        ev=cand[0]; del self.d[ev]; del self.freq[ev]
    def get(self,k):
        if k not in self.d: return -1
        self.freq[k]+=1; self.tick+=1; self.order[k]=self.tick; return self.d[k]
    def put(self,k,v):
        if k in self.d:
            self.d[k]=v; self.freq[k]+=1; self.tick+=1; self.order[k]=self.tick; return
        if self.cap<=0: return
        if len(self.d)>=self.cap: self._evict()
        self.d[k]=v; self.freq[k]=1; self.tick+=1; self.order[k]=self.tick

runtime_cases=[]  # LFU op sequences with expected outputs
ref=RefLFU(5)
ops=[]
for _ in range(60):
    if random.random()<0.5: ops.append(('g',random.randint(0,9)))
    else: ops.append(('p',random.randint(0,9),random.randint(0,30)))
exp=[]
for op in ops:
    if op[0]=='g': exp.append(ref.get(op[1]))
    else: ref.put(op[1],op[2]); exp.append(None)
runtime_cases.append((ops,exp))

def run_tests(code):
    ns={}
    try:
        exec(code, ns)
    except Exception as e:
        return {'ok':False,'reason':'exec error: '+str(e)[:150]}
    res={}
    # merge
    fn=None
    for k,v in ns.items():
        if callable(v) and ('merge' in k.lower()): fn=v; break
    if fn is None:
        res['merge']={'ok':False,'err':'no merge fn'}
    else:
        try:
            ok=True
            for ivs,e in merge_cases:
                if fn([list(x) for x in ivs])!=e: ok=False; break
            t0=time.time(); g=fn([list(x) for x in large_merge]); dt=time.time()-t0
            if g!=large_merge_exp: ok=False
            res['merge']={'ok':ok,'large_time':round(dt,2)}
        except Exception as e:
            res['merge']={'ok':False,'err':str(e)[:100]}
    # trap
    fn=None
    for k,v in ns.items():
        if callable(v) and ('trap' in k.lower() or 'rain' in k.lower()): fn=v; break
    if fn is None:
        res['trap']={'ok':False,'err':'no trap fn'}
    else:
        try:
            ok=True
            for h,e in trap_cases:
                if fn(list(h))!=e: ok=False; break
            t0=time.time(); g=fn(list(large_trap)); dt=time.time()-t0
            if g!=large_trap_exp: ok=False
            res['trap']={'ok':ok,'large_time':round(dt,2)}
        except Exception as e:
            res['trap']={'ok':False,'err':str(e)[:100]}
    # lfu
    try:
        cls=None
        for k,v in ns.items():
            if isinstance(v,type) and 'lfu' in k.lower(): cls=v; break
        if cls is None:
            # try any class with get+put
            for k,v in ns.items():
                if isinstance(v,type) and hasattr(v,'get') and hasattr(v,'put'): cls=v; break
        if cls is None:
            res['lfu']={'ok':False,'err':'no LFU class'}
        else:
            ok=True
            for ops,exp in runtime_cases:
                c=cls(5); got=[]
                for op in ops:
                    if op[0]=='g': got.append(c.get(op[1]))
                    else: c.put(op[1],op[2]); got.append(None)
                if got!=exp: ok=False; break
            res['lfu']={'ok':ok}
    except Exception as e:
        res['lfu']={'ok':False,'err':str(e)[:100]}
    all_ok=all(v.get('ok',False) for v in res.values())
    return {'ok':all_ok,'details':res}

if __name__=='__main__':
    code=sys.stdin.read()
    print(json.dumps(run_tests(code)))
