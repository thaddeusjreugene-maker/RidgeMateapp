// Ridgeline Teams — app module.
// Field tools (map, leads, camera, estimates, routes) plus team accounts, open leads, leaderboards and chat.
import { demoApi } from './api/demo.js';
let supabaseApi=null;
function loadSample(){}
/* ---------- constants ---------- */
const STATUSES=[
  {k:'Not Home',v:'--s-nothome',hollow:true},
  {k:'Not Interested',v:'--s-noint'},
  {k:'Follow Up',v:'--s-follow'},
  {k:'Be Back',v:'--s-beback'},
  {k:'Inspection Scheduled',v:'--s-sched'},
  {k:'Inspected',v:'--s-insp'},
  {k:'No Damage',v:'--s-nodmg'},
  {k:'Claim Pending',v:'--s-claim'},
  {k:'Sold',v:'--s-sold'},
  {k:'Cancelled',v:'--s-cancel'},
  {k:'Finance Denied',v:'--s-fin'}
];
const KNOCK_RESULTS=['Not Home','Not Interested','Follow Up','Be Back','Inspection Scheduled','Inspected','Sold'];
const LOST=['Not Interested','No Damage','Cancelled','Finance Denied'];
const DEAD=['Cancelled','Finance Denied'];
const THEMES={ember:['Ember','#F2541B','#FF8A3D'],cobalt:['Cobalt','#2F6BFF','#5AA0FF'],emerald:['Emerald','#0E9F6E','#34D399'],
  violet:['Violet','#7C3AED','#A78BFA'],crimson:['Crimson','#E11D48','#FB7185'],gold:['Gold','#C98A00','#F2B92C']};
const SMAP=Object.fromEntries(STATUSES.map(s=>[s.k,s]));
const SLOPES=['Front slope','Rear slope','Left slope','Right slope','Ridge / hips','Valleys','Soft metals','Gutters & downspouts','Siding / windows','Attic / interior','Elevation','Other'];
const DMG=['Hail','Wind','Wear / age','Mechanical','No damage','Overview'];
const PHASES=['Inspection','Before','After'];
const MARKS=[{k:'Hail',c:'#E5484D'},{k:'Wind',c:'#3E9BFF'},{k:'Other',c:'#F5B800'}];
const STAGES=['Contract signed','Claim filed','Adjuster meeting','Approved','Materials ordered','Installed','Final check paid'];
const JOBTYPES=['Insurance','Retail','Repair'];
const PRESETS=[
  {d:'Tear off & replace — architectural shingle',u:'SQ',p:450},
  {d:'Synthetic underlayment',u:'SQ',p:0},
  {d:'Ice & water shield',u:'SQ',p:95},
  {d:'Drip edge',u:'LF',p:3.5},
  {d:'Ridge vent',u:'LF',p:9},
  {d:'Pipe boots',u:'EA',p:45},
  {d:'Additional layer removal',u:'SQ',p:60},
  {d:'Permit',u:'EA',p:150}
];
const DEF_SETTINGS={repName:'',company:'',repPhone:'',city:'Lancaster, SC',rate:10,rateIns:10,rateRet:10,rateRep:10,goal:6000,theme:'ember',sessions:[],activeSession:null,
  terms:'By signing, the homeowner agrees to have the contractor perform the work listed above at the stated price, subject to insurance approval where marked Insurance. This agreement may be cancelled in writing within 3 business days.'};

/* ---------- state ---------- */
const S={uid:null,db:null,col:null,assets:null,dl:null,user:null,
  leads:new Map(),settings:{...DEF_SETTINGS},dirty:new Set(),deleted:new Set(),
  tab:'home',open:null,leadQ:'',leadF:'all',fuSeg:'due',streetF:'all',lastStreet:'',lastSlope:'Front slope',
  urls:new Map(),flushing:false,online:navigator.onLine,dbState:'starting',firstServer:false,uploading:false};

/* ---------- utils ---------- */
const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>[...r.querySelectorAll(s)];
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const rid=()=>Date.now().toString(36)+Math.random().toString(36).slice(2,8);
const num=v=>{const n=parseFloat(String(v??'').replace(/[^0-9.\-]/g,''));return isFinite(n)?n:0};
const money=n=>(n<0?'-':'')+'$'+Math.abs(Math.round(n||0)).toLocaleString('en-US');
const money2=n=>'$'+(Number(n)||0).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
const pad2=n=>String(n).padStart(2,'0');
const dayKey=d=>{d=new Date(d);return d.getFullYear()+'-'+pad2(d.getMonth()+1)+'-'+pad2(d.getDate())};
const localDT=d=>dayKey(d)+'T'+pad2(d.getHours())+':'+pad2(d.getMinutes());
const todayKey=()=>dayKey(Date.now());
const getP=(o,p)=>p.split('.').reduce((a,k)=>a==null?a:a[k],o);
const setP=(o,p,v)=>{const ks=p.split('.');let a=o;ks.slice(0,-1).forEach(k=>{if(a[k]==null||typeof a[k]!=='object')a[k]={};a=a[k]});a[ks.at(-1)]=v};
const clone=o=>JSON.parse(JSON.stringify(o));
const sv=k=>`var(${(SMAP[k]||SMAP['Not Home']).v})`;
function fmtWhen(s){if(!s)return'';const d=new Date(s);if(isNaN(d))return'';
  const tk=dayKey(d),t=todayKey(),tm=dayKey(Date.now()+864e5);
  const time=d.toLocaleTimeString([], {hour:'numeric',minute:'2-digit'});
  if(tk===t)return'Today '+time; if(tk===tm)return'Tomorrow '+time;
  return d.toLocaleDateString([], {weekday:'short',month:'short',day:'numeric'})+' '+time}
function fmtDate(t){if(!t)return'';const d=new Date(t);return isNaN(d)?'':d.toLocaleDateString([], {month:'short',day:'numeric',year:'numeric'})}
function fmtStamp(t){const d=new Date(t);return d.toLocaleDateString([], {month:'short',day:'numeric'})+' · '+d.toLocaleTimeString([], {hour:'numeric',minute:'2-digit'})}
function ago(t){const d=Math.floor((Date.now()-t)/864e5);return d<=0?'today':d===1?'yesterday':d+' days ago'}
const addr=l=>[l.num,l.street].filter(Boolean).join(' ')||'No address';
const fullAddr=l=>addr(l)+(l.city?', '+l.city:'');
const streetKey=s=>String(s||'').trim().toLowerCase().replace(/\s+/g,' ');
function toast(m){const t=document.createElement('div');t.className='toast';t.textContent=m;document.body.appendChild(t);setTimeout(()=>t.remove(),2200)}
function pill(k){const s=SMAP[k]||SMAP['Not Home'];return `<span class="pill${s.hollow?' hollow':''}" style="--c:${sv(k)}">${esc(k)}</span>`}

/* ---------- lead model ---------- */
function typeRate(t,origin){const r=wsSet().rates||{};const src=r[origin==='company'?'company':'self']||{};const v=src[t];return v!=null&&v!==''?num(v):10}
function commission(l){const s=l.sale;if(String(s.commOverride).trim()!=='')return num(s.commOverride);
  const base=jobTotal(l);let r;if(String(s.rate).trim()!=='')r=num(s.rate);else{const m=S.members.get(l.owner_id||S.me);const ov=m&&m.prefs&&m.prefs.rate;r=ov!=null&&ov!==''?num(ov):typeRate(s.type,l.origin)}return base*r/100}
function newLead(p={}){return{id:'lead-'+rid(),kind:'lead',created:Date.now(),updated:Date.now(),
  num:'',street:'',city:S.settings.city||'',name:'',phone:'',email:'',source:'Door knock',status:'Not Home',followAt:'',
  owner_id:S.me,created_by:S.me,origin:'self',knocks:[],log:[],fuDone:[],ref:false,roof:{},ins:{},storms:[],findings:'',photos:[],docs:[],
  sale:{type:'Insurance',value:'',upgrades:'',supplements:'',rate:'',commOverride:'',cstatus:'none',paidAt:'',soldAt:'',stage:''},
  est:{lines:[],notes:'',sig:null,sigName:'',sigAt:''},...p}}
function norm(l){const n=newLead();for(const k of Object.keys(n))if(l[k]==null)l[k]=clone(n[k]);
  for(const k of Object.keys(n.sale))if(l.sale[k]==null)l.sale[k]=n.sale[k];
  for(const k of Object.keys(n.est))if(l.est[k]==null)l.est[k]=clone(n.est[k]);return l}
function setStatus(l,k){if(l.status===k)return;l.status=k;l.knocks.push({t:Date.now(),r:k,...stamp()});
  if(k==='Sold'){if(!l.sale.soldAt)l.sale.soldAt=todayKey();if(l.sale.cstatus==='none')l.sale.cstatus='pending';autoFeed('sale',`sold a ${(l.sale.type||'roof').toLowerCase()} job on ${l.street||'the route'}`)}
  if(DEAD.includes(k)){if(l.sale.cstatus!=='paid')l.sale.cstatus='none';l.followAt=''}}
const jobTotal=l=>num(l.sale.value)+num(l.sale.upgrades)+num(l.sale.supplements);
const everHit=(l,set)=>set.includes(l.status)||l.knocks.some(k=>set.includes(k.r));
const estTotal=l=>l.est.lines.reduce((a,x)=>a+num(x.q)*num(x.p),0);

/* ---------- IndexedDB for photos waiting to upload ---------- */
let idbP=null;
function idb(){if(idbP)return idbP;idbP=new Promise((res,rej)=>{try{const r=indexedDB.open('ridgeline-files',1);
  r.onupgradeneeded=()=>r.result.createObjectStore('f');r.onsuccess=()=>res(r.result);r.onerror=()=>rej(r.error)}catch(e){rej(e)}});return idbP}
async function idbOp(mode,fn){const d=await idb();return new Promise((res,rej)=>{const tx=d.transaction('f',mode);const st=tx.objectStore('f');const r=fn(st);
  tx.oncomplete=()=>res(r&&r.result);tx.onerror=()=>rej(tx.error)})}
const idbPut=(k,v)=>idbOp('readwrite',s=>s.put(v,k));
const idbGet=k=>idbOp('readonly',s=>s.get(k));
const idbDel=k=>idbOp('readwrite',s=>s.delete(k));
const idbKeys=()=>idbOp('readonly',s=>s.getAllKeys());
async function hydrateUrls(){try{const keys=await idbKeys();for(const k of keys||[]){if(S.urls.has(k))continue;const b=await idbGet(k);if(b)S.urls.set(k,URL.createObjectURL(b))}}catch(e){}}
/* ---------- views ---------- */
function monthOf(t){const d=new Date(t);return d.getFullYear()*12+d.getMonth()}
const monthName=m=>new Date(Math.floor(m/12),m%12,1).toLocaleDateString([], {month:'long',year:'numeric'});
const dateMonth=s=>s?monthOf(s+'T12:00'):-1;
const hexRgb=h=>{h=String(h||'').trim().replace('#','');if(h.length===3)h=h.split('').map(c=>c+c).join('');const n=parseInt(h,16);return isFinite(n)&&h.length===6?[n>>16&255,n>>8&255,n&255]:null};
const rgbHex=a=>'#'+a.map(v=>Math.round(Math.max(0,Math.min(255,v))).toString(16).padStart(2,'0')).join('').toUpperCase();
const mixHex=(h,w,t)=>{const a=hexRgb(h)||[242,84,27],b=hexRgb(w)||[255,255,255];return rgbHex(a.map((v,i)=>v+(b[i]-v)*t))};
function accentPair(){const s=S.settings;if(s.theme==='custom'&&hexRgb(s.accent))return [s.accent,mixHex(s.accent,'#FFFFFF',.32)];const t=THEMES[s.theme]||THEMES.ember;return [t[1],t[2]]}
function applyTheme(){const s=S.settings,root=document.documentElement,r=root.style;const [a,b]=accentPair();r.setProperty('--accent',a);r.setProperty('--accent2',b);
  const sc=s.statusColors||{};for(const st of STATUSES){if(hexRgb(sc[st.k]))r.setProperty(st.v,sc[st.k]);else r.removeProperty(st.v)}
  const md=s.mode||'system';if(md==='system')root.removeAttribute('data-theme');else root.setAttribute('data-theme',md);
  $$('meta[name="theme-color"]').forEach(m=>{if(!m.dataset.orig)m.dataset.orig=m.content;m.content=md==='dark'?'#141922':md==='light'?'#FFFFFF':m.dataset.orig})}
function statusHex(st){const v=getComputedStyle(document.documentElement).getPropertyValue(st.v).trim();return hexRgb(v)?rgbHex(hexRgb(v)):'#888888'}
function colorsHTML(s){const md=s.mode||'system',[acc]=accentPair();
  return `<div class="label">Colors</div>
    <div class="field"><span>Appearance</span><div class="seg" role="radiogroup" aria-label="Appearance">${[['system','Auto'],['light','Light'],['dark','Dark']].map(([k,t])=>`<button role="radio" data-mode-pick="${k}" aria-selected="${md===k}">${t}</button>`).join('')}</div></div>
    <div class="field"><span>Accent color · buttons, highlights and your reports</span>
    <div class="themes" role="radiogroup" aria-label="Accent color">${Object.entries(THEMES).map(([k,t])=>`<button class="theme-sw" role="radio" data-theme-pick="${k}" aria-checked="${(s.theme||'ember')===k}" style="--a:${t[1]};--b:${t[2]}"><span></span>${t[0]}</button>`).join('')}
      <label class="theme-sw custom-sw" role="radio" aria-checked="${s.theme==='custom'}" style="--a:${acc};--b:${mixHex(acc,'#FFFFFF',.32)}"><span></span>Custom<input type="color" id="s-accent" value="${s.theme==='custom'&&hexRgb(s.accent)?s.accent:acc}" aria-label="Pick a custom accent color"></label></div></div>
    <details class="sc-box"><summary><span class="grow">Status & pin colors</span><span class="sc-dots">${STATUSES.slice(0,6).map(st=>`<i style="background:var(${st.v})"></i>`).join('')}</span></summary>
      <div class="sc-list">${STATUSES.map(st=>`<label class="sc-row"><span class="sc-sw" style="background:var(${st.v})"></span><span class="grow">${esc(st.k)}</span><input type="color" data-scol="${esc(st.k)}" value="${statusHex(st)}" aria-label="Color for ${esc(st.k)}"></label>`).join('')}</div>
      <button class="btn sm" data-scol-reset>Reset status colors</button></details>`}
function bindColors(m){const s=S.settings;
  const markAcc=()=>{$$('[data-theme-pick]',m).forEach(b=>b.setAttribute('aria-checked',b.dataset.themePick===s.theme));const c=$('.custom-sw',m);if(c){c.setAttribute('aria-checked',s.theme==='custom');const [a,b]=accentPair();if(s.theme==='custom'){c.style.setProperty('--a',a);c.style.setProperty('--b',b)}}};
  m.addEventListener('input',e=>{const t=e.target;
    if(t.id==='s-accent'){s.theme='custom';s.accent=t.value.toUpperCase();applyTheme();markAcc();clearTimeout(bindColors.t);bindColors.t=setTimeout(saveSettings,400);return}
    if(t.dataset.scol){s.statusColors=Object.assign({},s.statusColors,{[t.dataset.scol]:t.value.toUpperCase()});applyTheme();clearTimeout(bindColors.t);bindColors.t=setTimeout(()=>{saveSettings();if(MV.map)refreshPins()},400)}});
  m.addEventListener('click',e=>{const mp=e.target.closest('[data-mode-pick]');if(mp){s.mode=mp.dataset.modePick;applyTheme();saveSettings();$$('[data-mode-pick]',m).forEach(b=>b.setAttribute('aria-selected',b===mp));$$('[data-scol]',m).forEach(i=>{const st=SMAP[i.dataset.scol];if(st)i.value=statusHex(st)});return}
    if(e.target.closest('[data-scol-reset]')){s.statusColors={};applyTheme();saveSettings();$$('[data-scol]',m).forEach(i=>{const st=SMAP[i.dataset.scol];if(st)i.value=statusHex(st)});if(MV.map)refreshPins();toast('Status colors reset');return}
    if(e.target.closest('[data-theme-pick]'))setTimeout(markAcc,0)})}
function dur(ms){const s=Math.max(0,Math.floor(ms/1000));const h=Math.floor(s/3600),m=Math.floor(s%3600/60),x=s%60;return (h?h+':'+pad2(m):m)+':'+pad2(x)}

/* stats */
function windowStats(test){let k=0,c=0,a=0;for(const l of S.leads.values())for(const x of l.knocks){if(!test(x))continue;
  if(x.d){k++;if(x.r!=='Not Home')c++}if(x.r==='Inspection Scheduled')a++}return{k,c,a}}
function monthStats(m){const inM=t=>monthOf(t)===m;const w=windowStats(x=>inM(x.t));let insp=0,bb=0,can=0,fin=0;
  for(const l of S.leads.values())for(const x of l.knocks)if(inM(x.t)){if(x.r==='Inspected')insp++;if(x.r==='Be Back')bb++;if(x.r==='Cancelled')can++;if(x.r==='Finance Denied')fin++}
  const sold=leadsArr().filter(l=>dateMonth(l.sale.soldAt)===m&&!DEAD.includes(l.status)&&(l.status==='Sold'||l.sale.cstatus!=='none'));
  let paid=0;const paidJobs=leadsArr().filter(l=>l.sale.cstatus==='paid'&&dateMonth(l.sale.paidAt)===m);paidJobs.forEach(l=>paid+=commission(l));
  return{...w,insp,bb,can,fin,sold,paidJobs,vol:sold.reduce((a,l)=>a+jobTotal(l),0),comm:sold.reduce((a,l)=>a+commission(l),0),paid,
    close:insp?Math.min(100,Math.round(sold.length/insp*100)):0}}
function moneyNow(){const nowM=monthOf(Date.now());let paidM=0,owed=0,pend=0,pendM=0,paidAll=0;
  for(const l of leadsArr()){if(DEAD.includes(l.status)&&l.sale.cstatus!=='paid')continue;const c=commission(l),cs=l.sale.cstatus;
    if(cs==='paid'){paidAll+=c;if(dateMonth(l.sale.paidAt)===nowM)paidM+=c}
    else if(cs==='earned')owed+=c;
    else if(cs==='pending'){pend+=c;if(dateMonth(l.sale.soldAt)===nowM)pendM+=c}}
  return{paidM,owed,pend,pendM,paidAll,proj:paidM+owed+pendM}}
function calcStreak(){const days=new Set();for(const l of S.leads.values())for(const x of l.knocks)if(x.d)days.add(dayKey(x.t));
  const d=new Date();if(!days.has(dayKey(d)))d.setDate(d.getDate()-1);let n=0;while(days.has(dayKey(d))){n++;d.setDate(d.getDate()-1)}return n}
function followLists(){const now=Date.now(),tk=todayKey();
  const fu=leadsArr().filter(l=>l.followAt&&!LOST.includes(l.status)).sort((a,b)=>a.followAt.localeCompare(b.followAt));
  const done=[];for(const l of leadsArr())for(const d of l.fuDone||[])done.push({l,d});done.sort((a,b)=>b.d.t-a.d.t);
  return{overdue:fu.filter(l=>new Date(l.followAt).getTime()<now),
    today:fu.filter(l=>dayKey(l.followAt)===tk&&new Date(l.followAt).getTime()>=now),
    upcoming:fu.filter(l=>dayKey(l.followAt)>tk),done}}
function closeRateAll(){const L=leadsArr();const insp=L.filter(l=>everHit(l,['Inspected','Claim Pending','Sold','No Damage','Cancelled','Finance Denied'])).length;
  const won=L.filter(l=>l.status==='Sold').length;return insp?Math.round(won/insp*100):0}

/* rows */
const star=l=>l.ref?'<svg class="refstar" width="14" height="14" viewBox="0 0 24 24" aria-label="Reference customer"><path d="m12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z" fill="currentColor"/></svg>':'';
function leadRow(l,late){const w=l.followAt?fmtWhen(l.followAt):'';
  return `<button class="li" data-open="${l.id}"><span class="stripe" style="--c:${sv(l.status)}"></span>
  <span class="grow"><span class="t1 trunc" style="display:block">${star(l)}${esc(l.name||addr(l))}${l.example?'<span class="ex">EXAMPLE</span>':''}</span>
  <span class="t2 trunc" style="display:block">${esc(l.name?addr(l)+' · ':'')}${esc(l.status)}${viewAll()&&l.owner_id&&l.owner_id!==S.me?' · '+esc(mfirst(l.owner_id)):''}${l.pool?' · on the board':''}${l.sale.cstatus!=='none'&&!DEAD.includes(l.status)?' · '+money(commission(l)):''}</span></span>
  ${w?`<span class="when ${late?'late':''}">${esc(w)}</span>`:''}</button>`}
function fuRow(l,late){return `<div class="li fu"><span class="stripe" style="--c:${sv(l.status)}"></span>
  <button class="fu-open grow" data-open="${l.id}"><span class="t1 trunc" style="display:block">${star(l)}${esc(l.name||addr(l))}</span>
  <span class="t2 trunc" style="display:block">${esc(l.name?addr(l)+' · ':'')}${esc(l.status)}</span>
  <span class="when ${late?'late':''}" style="display:inline-block;margin-top:5px">${esc(fmtWhen(l.followAt))}</span></button>
  <button class="btn sm donebtn" data-fudone="${l.id}" aria-label="Mark follow-up done for ${esc(l.name||addr(l))}"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m5 12 5 5L20 7"/></svg>Done</button></div>`}
function routeUrl(ls){const a=ls.slice(0,10).map(fullAddr);if(!a.length)return'';const dest=a.pop();
  return 'https://www.google.com/maps/dir/?api=1&travelmode=driving&destination='+encodeURIComponent(dest)+(a.length?'&waypoints='+encodeURIComponent(a.join('|')):'')}

/* HOME */
function vHome(){
  const tk=todayKey(),nowM=monthOf(Date.now());const T=windowStats(x=>dayKey(x.t)===tk);const M=monthStats(nowM);const $m=moneyNow();
  const goal=num(S.settings.goal),pct=goal?Math.round($m.proj/goal*100):0,streak=calcStreak(),F=followLists(),act=S.settings.activeSession;
  const due=[...F.overdue,...F.today];const d=new Date();
  const first=S.settings.repName?S.settings.repName.split(' ')[0]:'';
  let h=`<div class="stack">
  <div class="row" style="align-items:flex-end"><div class="grow"><div class="label">${d.toLocaleDateString([], {weekday:'long',month:'long',day:'numeric'})}</div>
    <h1 style="font-size:30px;margin-top:2px">${first?'Let’s work, '+esc(first):'Let’s work'}</h1></div>
    ${streak?`<span class="streak" title="Days in a row with doors logged"><svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2c1 3.5 5 5.5 5 11a5 5 0 0 1-10 0c0-2.4 1-4 2.5-5.3C9.7 10 11 11 12 11c-1.5-3 0-6 0-9z" fill="currentColor"/></svg>${streak}-day streak</span>`:''}</div>
  ${S.dbState==='local'&&S.leads.size&&(!S.settings.lastBackup||Date.now()-S.settings.lastBackup>7*864e5)?`<div class="banner row" style="gap:10px"><span class="grow">${S.settings.lastBackup?'Last backup was '+ago(S.settings.lastBackup)+'.':'You haven’t backed up yet.'} Your leads and photos live only on this phone.</span><button class="btn sm pri" data-act="backupnow">Back up</button></div>`:''}
  ${RT.ids.length&&RT.idx<RT.ids.length?`<button class="card live-strip" data-act="openroute"><span class="rt-n" style="width:24px;height:24px">${RT.idx+1}</span><b>Route in progress</b><span class="muted">${RT.ids.length-RT.idx} stop${RT.ids.length-RT.idx>1?'s':''} left</span><span class="grow"></span><span class="muted">Open ›</span></button>`:''}
  ${act?`<button class="card live-strip" data-tab="knock"><span class="livedot"></span><b>Knocking session live</b><span class="muted num" id="sesstime2">${dur(Date.now()-act.start)}</span><span class="grow"></span><span class="muted">Open ›</span></button>`:''}
  <section class="card money-hero"><div class="label">${new Date().toLocaleDateString([], {month:'long'})} commission · projected</div>
    <div class="big">${money($m.proj)}</div>
    ${goal?`<div class="goalbar" role="img" aria-label="${pct}% of monthly goal"><span style="width:${Math.min(100,pct)}%"></span></div>
    <div class="row" style="justify-content:space-between;font-size:13px;margin-top:8px"><span class="muted">Goal ${money(goal)}</span><b class="num">${pct}%</b></div>`:''}
    <div class="hero-split"><div><span class="muted">Paid</span><b>${money($m.paidM)}</b></div><div><span class="muted">Owed</span><b>${money($m.owed)}</b></div><div><span class="muted">Pending</span><b>${money($m.pend)}</b></div></div>
  </section>
  <div><div class="sec-h"><h2>Today</h2></div><div class="kpis">
    <div class="card kpi"><b>${T.k}</b><span class="label">Doors</span></div>
    <div class="card kpi"><b>${T.c}</b><span class="label">Contacts</span></div>
    <div class="card kpi"><b>${T.a}</b><span class="label">Appts set</span></div></div></div>
  <div><div class="sec-h"><h2>This month</h2><button class="linkbtn" data-tab="money">Monthly view ›</button></div><div class="kpis">
    <div class="card kpi"><b>${M.sold.length}</b><span class="label">Sales</span></div>
    <div class="card kpi"><b>${closeRateAll()}%</b><span class="label">Close rate</span></div>
    <div class="card kpi"><b>${money(M.vol)}</b><span class="label">Volume</span></div></div></div>
  ${homeTools()}
  <section><div class="sec-h"><h2>Due now</h2><button class="linkbtn" data-tab="followups">All follow-ups ›</button></div>
    ${due.length?`<div class="card list">${due.slice(0,5).map(l=>fuRow(l,F.overdue.includes(l))).join('')}</div>`
      :`<div class="card empty"><strong>${S.leads.size?'You’re caught up':'No doors logged yet'}</strong>${S.leads.size?'Nothing overdue or due today.':'Tap <b>Knock</b> at your first house. Every door becomes a lead you can work from here.'}</div>`}</section>
  </div>`;
  return h}

/* KNOCK */
function streetsData(){const m=new Map();for(const l of leadsArr()){const k=streetKey(l.street)||'(no street)';
  if(!m.has(k))m.set(k,{name:l.street||'(no street)',leads:[],last:0});const s=m.get(k);s.leads.push(l);
  const lt=Math.max(l.updated||0,...l.knocks.map(x=>x.t));if(lt>s.last)s.last=lt}
  return [...m.values()].sort((a,b)=>b.last-a.last)}
function vKnock(){
  const act=S.settings.activeSession;let h='';
  if(act){const s=windowStats(x=>x.t>=act.start);const conv=s.k?Math.round(s.c/s.k*100):0;
    h+=`<section class="card sess live"><div class="row"><span class="livedot"></span><span class="label" style="color:var(--ok)">Session live</span><span class="grow"></span><span class="num sess-time" id="sesstime">${dur(Date.now()-act.start)}</span></div>
      <div class="sess-stats"><div><b>${s.k}</b><span>Doors</span></div><div><b>${s.c}</b><span>Contacts</span></div><div><b>${s.a}</b><span>Appts</span></div><div><b>${conv}%</b><span>Contact rate</span></div></div>
      <div class="btns"><button class="btn pri grow" data-act="knock">Log door</button><button class="btn" data-act="endsess">End session</button></div></section>`}
  else{const past=(S.settings.sessions||[]).slice(-4).reverse();
    h+=`<section class="card sess"><div class="row"><div class="grow"><h2 style="font-size:19px">Knocking session</h2><p class="muted" style="margin:4px 0 0;font-size:14px">Times your session and counts doors, contacts and appointments as you log them.</p></div></div>
      <button class="btn pri" data-act="startsess" style="width:100%"><svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4v16l13-8z" fill="currentColor"/></svg>Start session</button>
      ${past.length?`<div class="past">${past.map(p=>`<div class="past-row"><span>${esc(new Date(p.start).toLocaleDateString([], {weekday:'short',month:'short',day:'numeric'}))}</span><span class="muted num">${dur(p.end-p.start)}</span><span class="num"><b>${p.k}</b> doors · <b>${p.c}</b> contacts · <b>${p.a}</b> appts</span></div>`).join('')}</div>`:''}</section>`}
  const kv=S.knockView||'map';const sessH=h;
  const top=`<div class="stack"><div class="row"><h2 class="grow" style="font-size:28px;letter-spacing:-.03em">Map</h2><div class="seg seg2" role="tablist" aria-label="Knock view" style="width:190px"><button role="tab" data-kv="map" aria-selected="${kv==='map'}">Map</button><button role="tab" data-kv="list" aria-selected="${kv==='list'}">Streets</button></div></div>`;
  if(kv==='map')return top+mapHTML()+sessH+'</div>';
  h=top+sessH;
  const ss=streetsData(),f=S.streetF;
  h+=`<div class="sec-h" style="margin-top:6px"><h2>Streets</h2><span class="muted">${ss.length} worked</span></div>
  <div class="chips hscroll" role="group" aria-label="Highlight status"><button class="chip plain" data-sf="all" aria-pressed="${f==='all'}">All</button>${STATUSES.map(s=>`<button class="chip" style="--c:${sv(s.k)}" data-sf="${esc(s.k)}" aria-pressed="${f===s.k}"><span class="sw"></span>${esc(s.k)}</button>`).join('')}</div>`;
  if(!ss.length)h+=`<div class="card empty"><strong>No streets yet</strong>Each street you knock becomes a card here, with every house colored by its last result.</div>`;
  for(const s of ss){const ls=s.leads.slice().sort((a,b)=>num(a.num)-num(b.num));const counts={};ls.forEach(l=>counts[l.status]=(counts[l.status]||0)+1);
    const city=ls.find(l=>l.city)?.city||'';
    h+=`<section class="card pad street"><div class="row"><div class="grow"><h3 class="trunc">${esc(s.name)}</h3><div class="muted" style="font-size:13px">${ls.length} house${ls.length>1?'s':''} · worked ${ago(s.last)}${city?' · '+esc(city):''}</div></div>
      <a class="btn sm" target="_blank" rel="noopener" href="https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(s.name+(city?', '+city:''))}">Map</a></div>
      <div class="bar" aria-hidden="true">${STATUSES.filter(x=>counts[x.k]).map(x=>`<span style="--c:${sv(x.k)};flex:${counts[x.k]}"></span>`).join('')}</div>
      <div class="houses">${ls.map(l=>{const st=SMAP[l.status]||SMAP['Not Home'];const dim=f!=='all'&&l.status!==f;
        return `<button class="house${st.hollow?' hollow':''}${l.ref?' isref':''}" style="--c:${sv(l.status)};${dim?'opacity:.2':''}" data-open="${l.id}" title="${esc(addr(l)+' — '+l.status)}">${esc(l.num||'?')}</button>`}).join('')}</div>
      <form class="addhouse" data-addhouse="${esc(s.name)}" data-city="${esc(city)}"><input type="text" inputmode="numeric" placeholder="House #" aria-label="House number on ${esc(s.name)}" id="ah-${esc(streetKey(s.name)).replace(/[^a-z0-9]/g,'-')}"><button class="btn sm" type="submit">+ Knock here</button></form></section>`}
  return h+'</div>'}

/* PIPELINE */
function vPipeline(){
  const q=S.leadQ.toLowerCase(),f=S.leadF;const all=leadsArr();
  let L=all.filter(l=>(f==='all'||(f==='ref'?l.ref:f==='open'?!LOST.includes(l.status)&&l.status!=='Sold':l.status===f))&&(!q||[l.name,addr(l),l.phone,l.city,l.ins.carrier,l.ins.claim].join(' ').toLowerCase().includes(q)));
  L.sort((a,b)=>(b.updated||0)-(a.updated||0));
  const cnt=s=>all.filter(l=>l.status===s).length;
  const open=all.filter(l=>!LOST.includes(l.status)&&l.status!=='Sold').length,won=cnt('Sold'),lost=all.filter(l=>LOST.includes(l.status)).length;
  const pipeVal=all.filter(l=>['Sold','Claim Pending'].includes(l.status)&&l.sale.cstatus!=='paid').reduce((a,l)=>a+commission(l),0);
  let h=`<div class="stack"><div class="sec-h"><h2 style="font-size:28px;letter-spacing:-.03em">Pipeline</h2><span class="muted num">${all.length} leads</span></div>
  <div class="tri"><button class="card" data-lf="open" aria-pressed="${f==='open'}"><b>${open}</b><span>Open</span></button><button class="card" data-lf="Sold" aria-pressed="${f==='Sold'}"><b style="color:var(--s-sold)">${won}</b><span>Sold</span></button><button class="card" data-lf="all" aria-pressed="${f==='all'}"><b>${money(pipeVal)}</b><span>Unpaid comm.</span></button></div>
  <div class="search"><input type="search" id="leadq" placeholder="Search name, address, phone, claim #" value="${esc(S.leadQ)}" aria-label="Search leads"></div>
  <div class="chips hscroll"><button class="chip plain" data-lf="all" aria-pressed="${f==='all'}">All</button><button class="chip" style="--c:#C98A00" data-lf="ref" aria-pressed="${f==='ref'}"><span class="sw"></span>Reference</button>${STATUSES.map(s=>`<button class="chip" style="--c:${sv(s.k)}" data-lf="${esc(s.k)}" aria-pressed="${f===s.k}"><span class="sw"></span>${esc(s.k)} <span class="num" style="opacity:.7">${cnt(s.k)}</span></button>`).join('')}</div>`;
  h+=L.length?`<div class="card list">${L.map(l=>leadRow(l,l.followAt&&new Date(l.followAt)<Date.now())).join('')}</div>`:
    `<div class="card empty"><strong>${all.length?'No matches':'No leads yet'}</strong>${all.length?'Try another search or status.':'Every door you log lands here.'}</div>`;
  if(lost)h+=`<p class="muted" style="font-size:13px;margin:0 2px">${lost} lost · Be Backs, cancellations and finance denials are tracked separately on the Money tab.</p>`;
  return h+'</div>'}

/* FOLLOW-UPS */
function vFollow(){const F=followLists(),seg=S.fuSeg;const due=[...F.overdue,...F.today];
  const tabs=[['due','Due',due.length],['upcoming','Upcoming',F.upcoming.length],['done','Completed',F.done.length]];
  let h=`<div class="stack"><div class="sec-h"><h2 style="font-size:28px;letter-spacing:-.03em">Follow-ups</h2>${F.overdue.length?`<span class="pill" style="--c:var(--danger)">${F.overdue.length} overdue</span>`:''}</div>
  <div class="seg" role="tablist">${tabs.map(([k,t,n])=>`<button role="tab" data-fuseg="${k}" aria-selected="${seg===k}">${t} <span class="num">${n}</span></button>`).join('')}</div>`;
  if(seg==='due'){
    if(due.length)h+=`<button class="btn pri" data-act="planroute"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><circle cx="6" cy="19" r="2.5"/><circle cx="18" cy="5" r="2.5"/><path d="M8.5 19H16a3.5 3.5 0 0 0 0-7H8a3.5 3.5 0 0 1 0-7h7.5"/></svg>Plan route for ${due.length} stop${due.length>1?'s':''}</button>`;
    if(F.overdue.length)h+=`<section><div class="label" style="margin:0 2px 8px;color:var(--danger)">Overdue</div><div class="card list">${F.overdue.map(l=>fuRow(l,true)).join('')}</div></section>`;
    if(F.today.length)h+=`<section><div class="label" style="margin:0 2px 8px">Later today</div><div class="card list">${F.today.map(l=>fuRow(l)).join('')}</div></section>`;
    if(!due.length)h+=`<div class="card empty"><strong>All clear</strong>Nothing overdue or due today.</div>`}
  if(seg==='upcoming'){
    if(!F.upcoming.length)h+=`<div class="card empty"><strong>Nothing scheduled</strong>Set a follow-up on any lead and it lands here by date.</div>`;
    else{let last='',out='';for(const l of F.upcoming){const k=dayKey(l.followAt);if(k!==last){last=k;out+=`<div class="dayhdr">${new Date(l.followAt).toLocaleDateString([], {weekday:'long',month:'short',day:'numeric'})}</div>`}out+=fuRow(l)}
      h+=`<div class="card list">${out}</div>`}}
  if(seg==='done'){
    h+=F.done.length?`<div class="card list">${F.done.slice(0,60).map(({l,d})=>`<button class="li" data-open="${l.id}"><span class="stripe" style="--c:var(--ok)"></span><span class="grow"><span class="t1 trunc" style="display:block">${esc(l.name||addr(l))}</span><span class="t2 trunc" style="display:block">Done ${esc(fmtStamp(d.t))}${d.due?' · was due '+esc(fmtWhen(d.due)):''}</span></span></button>`).join('')}</div>`
      :`<div class="card empty"><strong>None completed yet</strong>Tap <b>Done</b> on a follow-up and it moves here.</div>`}
  return h+'</div>'}

/* MONEY */
function vMoney(){
  const $m=moneyNow(),nowM=monthOf(Date.now()),M=monthStats(nowM),goal=num(S.settings.goal),pct=goal?Math.round($m.proj/goal*100):0;
  const L=leadsArr();
  const earliest=L.reduce((a,l)=>Math.min(a,monthOf(l.created||Date.now())),nowM);
  const months=[];for(let m=nowM;m>=Math.max(earliest,nowM-11);m--)months.push(m);
  const paid=L.filter(l=>l.sale.cstatus==='paid').sort((a,b)=>String(b.sale.paidAt).localeCompare(String(a.sale.paidAt)));
  const sold=L.filter(l=>(l.status==='Sold'||l.sale.cstatus!=='none')&&!DEAD.includes(l.status));
  let h=`<div class="stack"><div class="sec-h"><h2 style="font-size:28px;letter-spacing:-.03em">Money</h2><span class="muted">${new Date().toLocaleDateString([], {month:'long'})}</span></div>
  <section class="card money-hero"><div class="label">Projected this month</div><div class="big">${money($m.proj)}</div>
    ${goal?`<div class="goalbar" role="img" aria-label="${pct}% of monthly goal"><span style="width:${Math.min(100,pct)}%"></span></div>
    <div class="row" style="justify-content:space-between;font-size:13px;margin-top:8px"><span class="muted">Goal ${money(goal)}</span><b class="num">${pct}%</b></div>`:''}
    <div class="hero-split"><div><span class="muted">Paid</span><b>${money($m.paidM)}</b></div><div><span class="muted">Owed</span><b>${money($m.owed)}</b></div><div><span class="muted">Pending</span><b>${money($m.pend)}</b></div></div></section>
  <section class="card pad"><div class="sec-h" style="margin-top:0"><h2>This month</h2><button class="linkbtn" data-month="${nowM}">Details ›</button></div>
    <div class="mgrid">
      <div><b>${M.k}</b><span>Doors</span></div><div><b>${M.c}</b><span>Contacts</span></div><div><b>${M.a}</b><span>Appts</span></div>
      <div><b>${M.insp}</b><span>Inspections</span></div><div><b style="color:var(--s-sold)">${M.sold.length}</b><span>Sales</span></div><div><b>${M.close}%</b><span>Close rate</span></div>
      <div><b style="color:var(--s-beback)">${M.bb}</b><span>Be Backs</span></div><div><b style="color:var(--s-cancel)">${M.can}</b><span>Cancelled</span></div><div><b style="color:var(--s-fin)">${M.fin}</b><span>Finance denied</span></div>
    </div></section>
  <section><div class="sec-h"><h2>Monthly view</h2></div><div class="card list">
    ${months.map(m=>{const x=monthStats(m);return `<button class="li" data-month="${m}"><span class="grow"><span class="t1" style="display:block">${esc(monthName(m))}</span><span class="t2" style="display:block">${x.sold.length} sale${x.sold.length===1?'':'s'} · ${money(x.vol)} volume · ${x.k} doors</span></span><span class="mval num">${money(x.comm)}</span><span class="muted">›</span></button>`}).join('')}
  </div></section>
  <section><div class="sec-h"><h2>Paydays</h2><span class="muted num">${money($m.paidAll)} all-time</span></div>
    ${paid.length?`<div class="card list">${paid.slice(0,30).map(l=>`<button class="li" data-open="${l.id}"><span class="payicon" aria-hidden="true">$</span><span class="grow"><span class="t1 trunc" style="display:block">${esc(l.name||addr(l))}</span><span class="t2" style="display:block">${esc(fmtDate(l.sale.paidAt+'T12:00'))} · ${esc(l.sale.type)}</span></span><b class="num" style="color:var(--ok)">+${money(commission(l))}</b></button>`).join('')}</div>`
      :`<div class="card empty"><strong>No paydays yet</strong>When you mark a commission <b>Paid</b>, it lands here as a receipt.</div>`}</section>`;
  if(sold.length)h+=`<section class="card"><div class="pad" style="padding-bottom:0"><h2 style="font-size:19px">Jobs</h2></div><div class="scroll-x"><table class="tbl"><thead><tr><th>Job</th><th>Stage</th><th class="r">Contract</th><th class="r">Comm.</th><th>Status</th></tr></thead><tbody>
    ${sold.sort((a,b)=>String(b.sale.soldAt).localeCompare(String(a.sale.soldAt))).map(l=>`<tr data-open="${l.id}" style="cursor:pointer"><td><b>${esc(l.name||addr(l))}</b><div class="muted" style="font-size:12px">${esc(l.sale.type)} · ${esc(fmtDate(l.sale.soldAt+'T12:00')||'')}</div></td><td>${esc(l.sale.stage||'—')}</td><td class="r">${money(jobTotal(l))}</td><td class="r"><b>${money(commission(l))}</b></td><td>${esc({none:'—',pending:'Pending',earned:'Owed',paid:'Paid'}[l.sale.cstatus])}</td></tr>`).join('')}
    </tbody></table></div></section>`;
  return h+'</div>'}

function monthModal(m){const x=monthStats(m);
  const md=modal(`<div class="row"><h2 class="grow">${esc(monthName(m))}</h2><button class="iconbtn" data-c="x" aria-label="Close">✕</button></div>
    <div class="mgrid"><div><b>${money(x.comm)}</b><span>Commission sold</span></div><div><b style="color:var(--ok)">${money(x.paid)}</b><span>Paid out</span></div><div><b>${money(x.vol)}</b><span>Volume</span></div>
      <div><b>${x.k}</b><span>Doors</span></div><div><b>${x.c}</b><span>Contacts</span></div><div><b>${x.a}</b><span>Appts</span></div>
      <div><b>${x.insp}</b><span>Inspections</span></div><div><b>${x.sold.length}</b><span>Sales</span></div><div><b>${x.close}%</b><span>Close rate</span></div>
      <div><b>${x.bb}</b><span>Be Backs</span></div><div><b>${x.can}</b><span>Cancelled</span></div><div><b>${x.fin}</b><span>Finance denied</span></div></div>
    ${x.sold.length?`<div class="card list" style="box-shadow:none;background:var(--sunk)">${x.sold.map(l=>`<button class="li" data-mopen="${l.id}"><span class="grow"><span class="t1 trunc" style="display:block">${esc(l.name||addr(l))}</span><span class="t2" style="display:block">${esc(l.sale.type)} · ${money(jobTotal(l))}</span></span><b class="num">${money(commission(l))}</b></button>`).join('')}</div>`:'<p class="muted" style="margin:0">No sales this month.</p>'}
    ${S.dl?`<div class="btns"><button class="btn" data-c="mcsv">Export CSV</button><button class="btn pri" data-c="mrep">Save month report</button></div>`:''}`);
  md.addEventListener('click',e=>{const o=e.target.closest('[data-mopen]');if(o){md.remove();openLead(o.dataset.mopen);return}
    const c=e.target.closest('[data-c]');if(!c)return;if(c.dataset.c==='x')md.remove();
    if(c.dataset.c==='mcsv'){const q=v=>{v=String(v??'');return /[",\n]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v};
      const rows=[['Homeowner','Address','Type','Sold','Contract','Upgrades','Supplements','Commission','Status','Paid']].concat(x.sold.map(l=>[l.name,fullAddr(l),l.sale.type,l.sale.soldAt,l.sale.value,l.sale.upgrades,l.sale.supplements,commission(l).toFixed(2),l.sale.cstatus,l.sale.paidAt]));
      save(`ridgeline-${monthName(m).replace(' ','-')}.csv`,rows.map(r=>r.map(q).join(',')).join('\n'))}
    if(c.dataset.c==='mrep'){const s=S.settings;const tr=(a,b)=>`<tr><th>${a}</th><td>${b}</td></tr>`;
      save(`Ridgeline ${monthName(m)}.html`,`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(monthName(m))} — sales report</title>
      <style>body{font-family:-apple-system,Segoe UI,Arial,sans-serif;max-width:760px;margin:0 auto;padding:28px;color:#111}h1{margin:0 0 4px;letter-spacing:-.02em}table{border-collapse:collapse;width:100%;margin-top:16px;font-size:14px}th,td{text-align:left;padding:7px 8px;border-bottom:1px solid #e5e5e5}td.r,th.r{text-align:right}</style></head><body>
      <h1>${esc(monthName(m))}</h1><div style="color:#666">${esc([s.repName,s.company].filter(Boolean).join(' · '))}</div>
      <table>${tr('Commission sold',money(x.comm))}${tr('Commission paid',money(x.paid))}${tr('Contract volume',money(x.vol))}${tr('Doors / contacts / appts',`${x.k} / ${x.c} / ${x.a}`)}${tr('Inspections',x.insp)}${tr('Sales',x.sold.length)}${tr('Close rate',x.close+'%')}${tr('Be Backs / cancelled / finance denied',`${x.bb} / ${x.can} / ${x.fin}`)}</table>
      <table><tr><th>Job</th><th>Type</th><th class="r">Contract</th><th class="r">Commission</th><th>Status</th></tr>${x.sold.map(l=>`<tr><td>${esc(l.name||'')}<br><span style="color:#777">${esc(fullAddr(l))}</span></td><td>${esc(l.sale.type)}</td><td class="r">${money(jobTotal(l))}</td><td class="r">${money(commission(l))}</td><td>${esc(l.sale.cstatus)}</td></tr>`).join('')}</table></body></html>`)}});
}

/* PAYDAY */
function celebrate(l){const amt=commission(l),nowM=monthOf(Date.now()),mPaid=monthStats(nowM).paid,goal=num(S.settings.goal);
  const hit=goal&&mPaid>=goal&&mPaid-amt<goal;
  const el=document.createElement('div');el.className='payday';el.setAttribute('role','dialog');el.setAttribute('aria-modal','true');
  el.innerHTML=`<canvas aria-hidden="true"></canvas><div class="pd-in"><div class="pd-label">Payday</div><div class="pd-amt num" id="pdamt">${money(amt)}</div>
    <div class="pd-who">${esc(l.name||addr(l))} · ${esc(l.sale.type)}</div>
    <div class="pd-month">${hit?'Monthly goal hit — ':''}${money(mPaid)} paid in ${new Date().toLocaleDateString([], {month:'long'})}</div>
    <button class="btn pri" data-act="pdclose">Collect</button></div>`;
  $('#layer').appendChild(el);
  if(matchMedia('(prefers-reduced-motion: reduce)').matches)return;
  const a=$('#pdamt',el);const t0=performance.now();const tick=t=>{const k=Math.min(1,(t-t0)/1100);a.textContent=money(amt*(1-Math.pow(1-k,3)));if(k<1)requestAnimationFrame(tick)};requestAnimationFrame(tick);
  const c=$('canvas',el),x=c.getContext('2d'),dpr=devicePixelRatio||1;c.width=innerWidth*dpr;c.height=innerHeight*dpr;x.scale(dpr,dpr);
  const th=THEMES[S.settings.theme]||THEMES.ember;const cols=[th[1],th[2],'#FFD34D','#2FCB72','#FFFFFF','#5B8CFF'];
  const P=Array.from({length:140},()=>({x:innerWidth/2+(Math.random()-.5)*80,y:innerHeight*.42,vx:(Math.random()-.5)*13,vy:-Math.random()*14-4,r:Math.random()*6+3,c:cols[Math.random()*cols.length|0],a:Math.random()*6,va:(Math.random()-.5)*.3}));
  const t1=performance.now();const draw=t=>{if(!el.isConnected)return;x.clearRect(0,0,innerWidth,innerHeight);
    for(const p of P){p.vy+=.35;p.vx*=.99;p.x+=p.vx;p.y+=p.vy;p.a+=p.va;x.save();x.translate(p.x,p.y);x.rotate(p.a);x.fillStyle=p.c;x.fillRect(-p.r/2,-p.r/4,p.r,p.r/2);x.restore()}
    if(t-t1<3200)requestAnimationFrame(draw);else x.clearRect(0,0,innerWidth,innerHeight)};requestAnimationFrame(draw)}

/* live session clock */
setInterval(()=>{const a=S.settings.activeSession;if(!a)return;const t=dur(Date.now()-a.start);const e1=$('#sesstime'),e2=$('#sesstime2');if(e1)e1.textContent=t;if(e2)e2.textContent=t},1000);

/* ---------- satellite map (Leaflet + Esri World Imagery) ---------- */
const ESRI='https://server.arcgisonline.com/ArcGIS/rest/services/';
const MAP_HOME=[34.7204,-80.7709];
const MV={map:null,host:null,pins:null,layers:{},base:'hybrid',temp:null,gps:{dot:null,acc:null,pos:null,watch:null,follow:false}};
function lsGet(k,d){try{const v=localStorage.getItem(k);return v?JSON.parse(v):d}catch(e){return d}}
function lsSet(k,v){try{localStorage.setItem(k,JSON.stringify(v))}catch(e){}}
function ensureMap(){
  if(MV.map||!window.L)return MV.map;
  const host=document.createElement('div');host.className='lmap';MV.host=host;
  const v=lsGet('ridgeline.mapview',null);
  const m=L.map(host,{zoomControl:false,attributionControl:true,maxZoom:21,tap:true,zoomSnap:.5,wheelPxPerZoomLevel:90}).setView(v?[v.lat,v.lng]:MAP_HOME,v?v.z:17);
  // load tiles while panning (not only after the finger lifts), keep extra tiles around the edges
  const fast={updateWhenIdle:false,updateWhenZooming:false,keepBuffer:4,crossOrigin:true};
  const key=(S.settings.mapboxKey||'').trim();
  MV.layers={
    sat:key?L.tileLayer('https://api.mapbox.com/v4/mapbox.satellite/{z}/{x}/{y}@2x.jpg90?access_token='+encodeURIComponent(key),{...fast,maxZoom:21,maxNativeZoom:21,attribution:'Imagery © Mapbox © Maxar'})
      :L.tileLayer('https://clarity.maptiles.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',{...fast,maxZoom:21,maxNativeZoom:19,attribution:'Imagery © Esri, Maxar, Earthstar Geographics'}),
    roads:L.tileLayer(ESRI+'Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',{...fast,maxZoom:21,maxNativeZoom:19}),
    street:L.tileLayer(ESRI+'World_Street_Map/MapServer/tile/{z}/{y}/{x}',{...fast,maxZoom:21,maxNativeZoom:19,attribution:'Map © Esri'})};
  let ok=0,bad=0;MV.layers.sat.on('tileload',()=>ok++);
  MV.layers.sat.on('tileerror',()=>{bad++;if(key){if(!MV.warned){MV.warned=1;toast('Mapbox key isn’t working — check it in Settings')}return}
    // Clarity unavailable here: fall back to the standard Esri imagery
    if(!ok&&bad>6&&!MV.fellBack){MV.fellBack=1;MV.layers.sat.setUrl(ESRI+'World_Imagery/MapServer/tile/{z}/{y}/{x}')}});
  MV.base=lsGet('ridgeline.mapbase','hybrid');setBase(MV.base,m);
  MV.pins=L.layerGroup().addTo(m);
  m.attributionControl.setPrefix(false);
  m.on('moveend',()=>{const c=m.getCenter();lsSet('ridgeline.mapview',{lat:c.lat,lng:c.lng,z:m.getZoom()});clearTimeout(ST.moveT);ST.moveT=setTimeout(()=>{if(stormOn())stormLoad()},350)});
  m.on('dragstart',()=>{MV.gps.follow=false});
  m.on('click',e=>{const md=S.mapMode||'browse';if(md==='pin')pinAt(e.latlng);else if(md==='terr')addTerrPoint(e.latlng);else if(md==='skip')addSkipPoint(e.latlng);else if(S.selPin||ST.sel||S.selZone){S.selPin=null;ST.sel=null;S.selZone=null;render()}});
  MV.map=m;return m}
function setBase(b,m=MV.map){const Lr=MV.layers;Object.values(Lr).forEach(l=>m.hasLayer(l)&&m.removeLayer(l));
  if(b==='street')Lr.street.addTo(m);else{Lr.sat.addTo(m);if(b==='hybrid')Lr.roads.addTo(m)}
  MV.base=b;lsSet('ridgeline.mapbase',b)}
function mapStreets(){return[]}
/* ---------- route planning ---------- */
const RT=Object.assign({ids:[],idx:0,geom:null,dist:0,dur:0,road:false,busy:false},lsGet('ridgeline.route',{}));
function saveRoute(){lsSet('rlt.route.'+S.me+'.'+(S.ws&&S.ws.id),{ids:RT.ids,idx:RT.idx,geom:RT.geom,dist:RT.dist,dur:RT.dur,road:RT.road})}
function routeLeads(){RT.ids=RT.ids.filter(id=>S.leads.has(id));return RT.ids.map(id=>S.leads.get(id))}
const hav=(a,b)=>{const R=3958.8,r=x=>x*Math.PI/180,dl=r(b.lat-a.lat),dg=r(b.lng-a.lng);
  const h=Math.sin(dl/2)**2+Math.cos(r(a.lat))*Math.cos(r(b.lat))*Math.sin(dg/2)**2;return 2*R*Math.asin(Math.sqrt(h))};
function orderStops(start,ls){ // nearest neighbor, then 2-opt on straight-line miles
  const pts=ls.filter(l=>l.geo);if(pts.length<2)return pts;
  let cur=start||pts[0].geo,left=pts.slice(),out=[];
  while(left.length){let bi=0,bd=Infinity;left.forEach((l,i)=>{const d=hav(cur,l.geo);if(d<bd){bd=d;bi=i}});const n=left.splice(bi,1)[0];out.push(n);cur=n.geo}
  const P=[start,...out.map(l=>l.geo)].filter(Boolean),off=start?1:0;const len=a=>{let s=0;for(let i=1;i<a.length;i++)s+=hav(a[i-1],a[i]);return s};
  let arr=out.slice(),best=len(start?[start,...arr.map(l=>l.geo)]:arr.map(l=>l.geo)),improved=true,guard=0;
  while(improved&&guard++<60){improved=false;
    for(let i=0;i<arr.length-1;i++)for(let k=i+1;k<arr.length;k++){const c=arr.slice(0,i).concat(arr.slice(i,k+1).reverse(),arr.slice(k+1));
      const L2=len(start?[start,...c.map(l=>l.geo)]:c.map(l=>l.geo));if(L2+1e-9<best){best=L2;arr=c;improved=true}}}
  return arr}
async function fetchRoad(points){
  if(points.length<2)return null;const coords=points.slice(0,25).map(p=>`${p.lng.toFixed(6)},${p.lat.toFixed(6)}`).join(';');
  const key=(S.settings.mapboxKey||'').trim();
  const url=key?`https://api.mapbox.com/directions/v5/mapbox/driving/${coords}?geometries=geojson&overview=full&access_token=${encodeURIComponent(key)}`
    :`https://router.project-osrm.org/route/v1/driving/${coords}?overview=full&geometries=geojson`;
  try{const ac=new AbortController();setTimeout(()=>ac.abort(),9000);const r=await fetch(url,{signal:ac.signal});if(!r.ok)return null;const j=await r.json();
    const rt=j.routes&&j.routes[0];if(!rt)return null;return{geom:rt.geometry.coordinates.map(c=>[c[1],c[0]]),dist:rt.distance/1609.34,dur:rt.duration/60}}catch(e){return null}}
async function buildRoute({optimize}={}){
  if(RT.busy)return;RT.busy=true;render();
  try{let ls=routeLeads();
    const missing=ls.filter(l=>!l.geo);
    for(const l of missing){const g=await geocode(fullAddr(l));if(g){l.geo=g;saveLead(l,{quiet:true})}await new Promise(r=>setTimeout(r,1100))}
    const skipped=ls.filter(l=>!l.geo);ls=ls.filter(l=>l.geo);
    const start=MV.gps.pos||null;
    if(optimize){const done=ls.slice(0,RT.idx),rest=ls.slice(RT.idx);ls=done.concat(orderStops(start,rest));}
    RT.ids=ls.map(l=>l.id).concat(skipped.map(l=>l.id));
    const pts=[...(start&&RT.idx<ls.length?[start]:[]),...ls.slice(RT.idx).map(l=>l.geo)];
    const road=await fetchRoad(pts);
    if(road){RT.geom=road.geom;RT.dist=road.dist;RT.dur=road.dur;RT.road=true}
    else{RT.geom=pts.map(p=>[p.lat,p.lng]);let d=0;for(let i=1;i<pts.length;i++)d+=hav(pts[i-1],pts[i]);RT.dist=d*1.3;RT.dur=RT.dist/25*60;RT.road=false}
    if(skipped.length)toast(`${skipped.length} stop${skipped.length>1?'s':''} couldn’t be found on the map — pin ${skipped.length>1?'them':'it'} first`);
    saveRoute();
    if(MV.map&&RT.geom&&RT.geom.length>1)MV.map.fitBounds(RT.geom,{paddingTopLeft:[30,80],paddingBottomRight:[30,S.rtList?380:250],maxZoom:18});
  }finally{RT.busy=false;render()}}
function drawRoute(){if(!MV.map)return;if(MV.routeLine){MV.map.removeLayer(MV.routeLine);MV.routeLine=null}
  if((S.mapMode||'browse')!=='route'&&!RT.ids.length)return;
  if(RT.geom&&RT.geom.length>1){const th=THEMES[S.settings.theme]||THEMES.ember;
    MV.routeLine=L.layerGroup([L.polyline(RT.geom,{color:'#fff',weight:9,opacity:.9,interactive:false}),L.polyline(RT.geom,{color:th[1],weight:5,opacity:1,interactive:false,dashArray:RT.road?null:'8 10'})]).addTo(MV.map)}}
function addToRoute(ids){let n=0;for(const id of ids)if(!RT.ids.includes(id)){RT.ids.push(id);n++}saveRoute();return n}
function dueLeadIds(){const F=followLists();const tk=todayKey();
  const insp=leadsArr().filter(l=>l.status==='Inspection Scheduled'&&l.followAt&&dayKey(l.followAt)<=tk);
  return [...new Set([...F.overdue,...F.today,...insp].map(l=>l.id))]}
function fmtDur(m){m=Math.round(m);return m<60?m+' min':Math.floor(m/60)+' hr '+(m%60)+' min'}
function routeCard(){const ls=routeLeads();const next=ls[RT.idx];
  const head=ls.length?`${ls.length} stop${ls.length>1?'s':''} · ${RT.dist?RT.dist.toFixed(1)+' mi':'—'} · ${RT.dur?fmtDur(RT.dur):'—'}${RT.geom&&!RT.road?' (est.)':''}`:'No stops yet';
  const gUrl=ls.length?'https://www.google.com/maps/dir/?api=1&travelmode=driving&destination='+encodeURIComponent(ls.at(-1).geo?ls.at(-1).geo.lat+','+ls.at(-1).geo.lng:fullAddr(ls.at(-1)))
    +(ls.length>1?'&waypoints='+encodeURIComponent(ls.slice(RT.idx,-1).slice(0,9).map(l=>l.geo?l.geo.lat+','+l.geo.lng:fullAddr(l)).join('|')):''):'';
  return `<div class="map-pop card route-card"><div class="row"><span class="grow"><span style="display:block;font-weight:800">Route</span><span class="muted" style="font-size:13px">${RT.busy?'Working out the route…':head}</span></span>
      ${ls.length?`<button class="btn sm" data-rt="opt" ${RT.busy?'disabled':''}>Optimize</button><button class="btn sm dng" data-rt="clear">Clear</button>`:''}</div>
    ${next?`<div class="rt-next"><span class="rt-n">${RT.idx+1}</span><span class="grow"><span class="label" style="font-size:10.5px">Next stop</span><span class="t1 trunc" style="display:block;font-weight:800">${esc(next.name||addr(next))}</span><span class="muted trunc" style="display:block;font-size:12.5px">${esc(next.name?addr(next)+' · ':'')}${esc(next.status)}</span></span></div>
      <div class="btns"><a class="btn pri grow" target="_blank" rel="noopener" href="https://maps.apple.com/?dirflg=d&daddr=${next.geo?next.geo.lat+','+next.geo.lng:encodeURIComponent(fullAddr(next))}">Drive in Apple Maps</a><button class="btn" data-rt="done">Arrived ✓</button></div>`
      :ls.length?`<div class="banner">Route finished. Nice work.</div>`:''}
    ${ls.length&&(S.rtList||!next)?`<div class="rt-list">${ls.map((l,i)=>`<div class="rt-row${i<RT.idx?' past':''}${i===RT.idx?' cur':''}"><span class="rt-n">${i+1}</span><button class="grow fu-open" data-open="${l.id}"><span class="trunc" style="display:block;font-weight:700;font-size:14px">${esc(l.name||addr(l))}</span><span class="muted trunc" style="display:block;font-size:12px">${esc(l.name?addr(l)+' · ':'')}${esc(l.status)}${l.followAt?' · '+esc(fmtWhen(l.followAt)):''}${l.geo?'':' · not on map'}</span></button><button class="iconbtn" data-rtdel="${l.id}" aria-label="Remove stop">✕</button></div>`).join('')}</div>`:''}
    <div class="btns">${ls.length&&next?`<button class="btn sm" data-rt="list">${S.rtList?'Hide stops':'All stops ('+ls.length+')'}</button>`:''}<button class="btn sm" data-rt="due">+ Today’s follow-ups</button>${ls.length>1?`<a class="btn sm" target="_blank" rel="noopener" href="${esc(gUrl)}">Whole route in Google Maps</a>`:''}</div>
    ${!ls.length?'<p class="muted" style="margin:0;font-size:13px">Tap pins on the map to add stops, or pull in everything due today.</p>':''}</div>`}
async function routeAction(k){
  if(k==='due'){const n=addToRoute(dueLeadIds());toast(n?`Added ${n} stop${n>1?'s':''}`:'Nothing due today that isn’t already on the route');if(n)await buildRoute({optimize:true});else render();return}
  if(k==='opt'){await buildRoute({optimize:true});toast('Stops reordered for the shortest drive');return}
  if(k==='list'){S.rtList=!S.rtList;render();return}
  if(k==='clear'){RT.ids=[];RT.idx=0;RT.geom=null;RT.dist=RT.dur=0;saveRoute();render();return}
  if(k==='done'){RT.idx=Math.min(RT.idx+1,RT.ids.length);saveRoute();const l=routeLeads()[RT.idx-1];if(l)openLead(l.id);await buildRoute({optimize:false});return}}
function bindMap(){const slot=$('#mapslot');if(!slot)return;const m=ensureMap();if(!m)return;
  slot.appendChild(MV.host);setTimeout(()=>m.invalidateSize(),0);
  MV.host.classList.toggle('pinmode',(S.mapMode||'browse')==='pin');refreshPins();
  if(S.flyTo){const f=S.flyTo;S.flyTo=null;m.setView([f.lat,f.lng],f.z||19)}
  setTimeout(()=>{if(S.stormFit){const pts=S.stormFit;S.stormFit=null;m.fitBounds(pts,{padding:[40,40],maxZoom:14})}
    if(S.stormCenter){const c=S.stormCenter;S.stormCenter=null;m.setView([c.lat,c.lng],Math.max(m.getZoom(),13),{animate:false});m.panBy([0,Math.round(m.getSize().y*.27)],{animate:false})}
    if(stormOn())stormLoad();else drawStorms()},30)}
async function revGeo(ll){try{const ac=new AbortController();setTimeout(()=>ac.abort(),4000);const r=await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&zoom=18&lat=${ll.lat}&lon=${ll.lng}`,{signal:ac.signal,headers:{'Accept-Language':'en'}});
  if(!r.ok)return{};const j=await r.json();const a=j.address||{};
  const city=a.city||a.town||a.village||a.hamlet||a.county||'';const stc=(a['ISO3166-2-lvl4']||'').split('-')[1]||a.state||'';
  return{num:a.house_number||'',street:a.road||'',city:[city,stc].filter(Boolean).join(', ')}}catch(e){return{}}}
async function geocode(q){try{const ac=new AbortController();setTimeout(()=>ac.abort(),6000);const r=await fetch(`https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=us&q=${encodeURIComponent(q)}`,{signal:ac.signal});const j=await r.json();
  return j&&j[0]?{lat:+j[0].lat,lng:+j[0].lon}:null}catch(e){return null}}
async function pinAt(ll){
  const near=leadsArr().find(l=>l.geo&&MV.map.distance([l.geo.lat,l.geo.lng],ll)<8);if(near){S.selPin=near.id;render();return}
  const geo={lat:+ll.lat.toFixed(6),lng:+ll.lng.toFixed(6)};
  {const z=zoneAt(ll);if(z)toast(`Heads up: inside skip zone “${z.name}”`)}
  if(S.rePin){const l=S.leads.get(S.rePin);S.rePin=null;if(l){l.geo=geo;saveLead(l);S.mapMode='browse';S.selPin=l.id;render();toast('Pin moved')}return}
  if(MV.temp)MV.map.removeLayer(MV.temp);
  MV.temp=L.marker(ll,{icon:L.divIcon({className:'mk-wrap',iconSize:[34,44],iconAnchor:[17,41],html:'<div class="mk temp"><b></b><span>…</span></div>'})}).addTo(MV.map);
  const a=await revGeo(ll);if(MV.temp){MV.map.removeLayer(MV.temp);MV.temp=null}
  knockModal({num:a.num||'',street:a.street||S.lastStreet,city:a.city||S.settings.city,geo})}
function toggleGPS(){if(!navigator.geolocation){toast('Location isn’t available on this device');return}
  const g=MV.gps;if(g.watch!=null&&g.pos){g.follow=true;MV.map.setView([g.pos.lat,g.pos.lng],Math.max(MV.map.getZoom(),19));return}
  g.follow=true;toast('Finding you…');
  g.watch=navigator.geolocation.watchPosition(p=>{const ll={lat:p.coords.latitude,lng:p.coords.longitude};const first=!g.pos;g.pos=ll;
      if(!g.dot){g.acc=L.circle(ll,{radius:p.coords.accuracy,className:'gps-acc',interactive:false}).addTo(MV.map);g.dot=L.circleMarker(ll,{radius:8,className:'gps-dot',interactive:false}).addTo(MV.map)}
      else{g.dot.setLatLng(ll);g.acc.setLatLng(ll).setRadius(p.coords.accuracy)}
      if(g.follow)MV.map.setView(ll,first?19:MV.map.getZoom(),{animate:!first});if(first&&S.tab==='knock')render()},
    e=>{toast(e.code===1?'Location is off for this app — allow it in Settings › Safari › Location':'Can’t get your location right now');navigator.geolocation.clearWatch(g.watch);g.watch=null},
    {enableHighAccuracy:true,maximumAge:5000,timeout:20000});
  render()}
/* ---------- roof calc ---------- */
function roofCalc(l){const c=l.roof.calc||{};const area=num(c.area)||num(c.len)*num(c.wid);const pitch=num(c.pitch);
  const waste=String(c.waste??'').trim()!==''?num(c.waste):({simple:10,hip:15,cut:20}[c.cx||'simple']);const f=Math.sqrt(1+(pitch/12)**2);
  return{area,pitch,waste,roofArea:area*f,sq:area?area*f*(1+waste/100)/100:0}}
function calcText(l){const r=roofCalc(l);return r.area?`${Math.round(r.roofArea).toLocaleString()} sq ft of roof + ${r.waste}% waste`:'Enter length × width or footprint'}
/* ---------- lead sheet ---------- */
function openLead(id){S.open=id;renderSheet(true)}
function closeLead(){S.open=null;$('#layer .sheet')?.remove();render()}
function renderSheet(first,noFetch){
  const l=S.leads.get(S.open);if(!l){closeLead();return}
  let el=$('#layer .sheet');const keepScroll=el?el.scrollTop:0;const openSecs=el?$$('details[data-sec]',el).filter(d=>d.open).map(d=>d.dataset.sec):null;
  if(!el){el=document.createElement('div');el.className='sheet';el.setAttribute('role','dialog');el.setAttribute('aria-modal','true');$('#layer').appendChild(el)}
  el.dataset.lead=l.id;el.innerHTML=sheetHTML(l,openSecs);if(!first)el.scrollTop=keepScroll;if(!noFetch)afterSheet(l);
  if($('#sigpad',el))initSig($('#sigpad',el));
}
function sec(id,title,body,openSecs,def,extra=''){const open=openSecs?openSecs.includes(id):def;
  return `<details class="sect" data-sec="${id}" ${open?'open':''}><summary><h2>${title}</h2>${extra}<svg class="chev" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg></summary><div class="sect-in">${body}</div></details>`}
const inp=(f,lab,l,type='text',ph='',attrs='')=>`<label class="field"><span>${lab}</span><input type="${type}" data-f="${f}" id="f-${f.replace(/\./g,'-')}" value="${esc(getP(l,f)??'')}" placeholder="${esc(ph)}" ${attrs}></label>`;
const sel=(f,lab,l,opts)=>`<label class="field"><span>${lab}</span><select data-f="${f}" id="f-${f.replace(/\./g,'-')}">${opts.map(o=>{const [v,t]=Array.isArray(o)?o:[o,o];return `<option value="${esc(v)}" ${String(getP(l,f)??'')===String(v)?'selected':''}>${esc(t)}</option>`}).join('')}</select></label>`;
const ta=(f,lab,l,ph='')=>`<label class="field"><span>${lab}</span><textarea data-f="${f}" id="f-${f.replace(/\./g,'-')}" placeholder="${esc(ph)}">${esc(getP(l,f)??'')}</textarea></label>`;

function sheetHTML(l,os){
  const A=encodeURIComponent(fullAddr(l));
  const late=l.followAt&&new Date(l.followAt)<Date.now();
  const tel=String(l.phone||'').replace(/[^0-9+]/g,'');
  const hdr=`<div class="sheet-top"><div class="row gut" style="max-width:760px;margin:0 auto">
    <button class="iconbtn" data-act="close" aria-label="Back"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg></button>
    <div class="grow trunc" style="font-weight:600">${esc(addr(l))}</div>
    <button class="iconbtn refbtn${l.ref?' on':''}" data-act="ref" aria-pressed="${!!l.ref}" aria-label="Reference customer" title="Reference customer"><svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true"><path d="m12 2 3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z" fill="${l.ref?'currentColor':'none'}" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg></button>
    <button class="btn sm" data-act="report">Report</button></div></div>`;
  const statusChips=`<div class="chips" role="group" aria-label="Lead status">${STATUSES.map(s=>`<button class="chip" style="--c:${sv(s.k)}" data-status="${esc(s.k)}" aria-pressed="${l.status===s.k}"><span class="sw"></span>${esc(s.k)}</button>`).join('')}</div>`;
  const qa=`<div class="qa">
    <a class="btn" href="${tel?'tel:'+tel:'#'}" ${tel?'':'aria-disabled="true" style="opacity:.45;pointer-events:none"'}><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/></svg>Call</a>
    <a class="btn" href="${tel?'sms:'+tel:'#'}" ${tel?'':'aria-disabled="true" style="opacity:.45;pointer-events:none"'}><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>Text</a>
    <a class="btn" target="_blank" rel="noopener" href="https://maps.apple.com/?daddr=${A}"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="m3 11 19-9-9 19-2-8-8-2z"/></svg>Drive</a>
    <a class="btn" target="_blank" rel="noopener" href="https://www.google.com/maps/search/?api=1&query=${A}"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M1 6v16l7-4 8 4 7-4V2l-7 4-8-4-7 4z"/><path d="M8 2v16M16 6v16"/></svg>Aerial</a></div>`;

  // follow-up
  const fuBody=`<div class="row" style="flex-wrap:wrap">${l.followAt?`<span class="pill" style="--c:${late?'var(--danger)':'var(--s-sched)'}">${late?'Overdue · ':''}${esc(fmtWhen(l.followAt))}</span>`:'<span class="muted">No follow-up set</span>'}</div>
    <div class="btns"><button class="btn sm" data-fu="tom">Tomorrow 10 AM</button><button class="btn sm" data-fu="3d">In 3 days</button><button class="btn sm" data-fu="1w">Next week</button><button class="btn sm" data-fu="spring">Spring</button>${l.followAt?'<button class="btn sm dng" data-fu="clear">Clear</button>':''}</div>
    ${l.followAt?`<button class="btn pri" data-fudone="${l.id}">Mark follow-up done</button>`:''}
    ${inp('followAt','Exact date & time',l,'datetime-local')}`;

  const contact=`<div class="grid2">${inp('num','House #',l,'text','','inputmode="numeric"')}${inp('street','Street',l,'text','Maple Ridge Dr','list="streetlist"')}</div>
    ${inp('city','City, state',l,'text','Lancaster, SC')}
    ${inp('name','Homeowner',l,'text','Full name','autocomplete="off"')}
    <div class="grid2">${inp('phone','Phone',l,'tel','','autocomplete="off"')}${inp('email','Email',l,'email','','autocomplete="off"')}</div>
    ${tel?`<div class="phone-line"><span class="muted">Number:</span><b>${esc(l.phone)}</b><button class="btn sm" data-copy="${esc(l.phone)}">Copy</button></div>`:''}
    <div class="grid2">${sel('source','Lead source',l,['Door knock','Referral','Yard sign','Inbound call','Company lead','Social media','Other'])}<label class="field"><span>First contact</span><input type="text" value="${esc(fmtDate(l.created))}" disabled></label></div>
    <button class="btn sm" data-act="findmap" style="align-self:flex-start"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><path d="M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12z"/><circle cx="12" cy="9" r="2.5"/></svg>${l.geo?'Show on map':'Place on map'}</button>
    <button class="btn sm" data-act="addroute" style="align-self:flex-start">${RT.ids.includes(l.id)?'On your route ✓':'+ Add to route'}</button>
    <datalist id="streetlist">${streetsData().map(s=>`<option value="${esc(s.name)}">`).join('')}</datalist>`;

  // notes / history
  const hist=[...l.log.map(x=>({t:x.t,h:esc(x.text),k:'note'})),...l.knocks.map(k=>({t:k.t,h:(SMAP[k.r]?'Status → '+pill(k.r):esc(k.r))+(isCompany()&&k.by?' <span class="muted">· '+esc(mfirst(k.by))+'</span>':''),k:'status'}))].sort((a,b)=>b.t-a.t);
  const notes=`<div class="row" style="align-items:flex-end"><label class="field grow"><span>Add a note</span><textarea id="newnote" placeholder="What they said, who to ask for, best time to call…" style="min-height:64px"></textarea></label></div>
    <div><button class="btn pri sm" data-act="addnote">Save note</button></div>
    ${hist.length?`<div class="list" style="border-top:1px solid var(--line)">${hist.map(x=>`<div class="li" style="cursor:default;align-items:flex-start"><span class="grow"><span style="display:block">${x.h}</span><span class="t2">${fmtStamp(x.t)}</span></span></div>`).join('')}</div>`:'<span class="muted">No history yet.</span>'}`;

  // photos
  const pending=l.photos.filter(p=>!p.asset).length;
  const groups={};l.photos.forEach((p,i)=>{(groups[p.slope]=groups[p.slope]||[]).push([p,i])});
  const order=SLOPES.filter(s=>groups[s]).concat(Object.keys(groups).filter(s=>!SLOPES.includes(s)));
  const photos=`<div class="cam">
      <label class="btn pri"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>Take photo<input type="file" accept="image/*" capture="environment" data-photo="camera" aria-label="Take roof photo"></label>
      <label class="btn"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg>Add existing<input type="file" accept="image/*" multiple data-photo="library" aria-label="Add photos"></label></div>
    <div class="row" style="flex-wrap:wrap;gap:8px"><span class="muted" style="font-size:13.5px">New photos file under</span>
      <select id="newslope" aria-label="Slope for new photos" style="width:auto;min-height:38px;padding:6px 8px">${SLOPES.map(s=>`<option ${s===S.lastSlope?'selected':''}>${s}</option>`).join('')}</select></div>
    ${pending&&S.assets?`<div class="banner">${pending} photo${pending>1?'s':''} saved on this phone, waiting to back up${S.assets?'':' (cloud photo backup isn’t available in this view)'}.</div>`:''}
    ${l.photos.length?order.map(g=>`<div class="ph-group"><div class="label" style="margin-bottom:6px">${esc(g)} · ${groups[g].length}</div><div class="ph-grid">${groups[g].map(([p,i])=>{const s=fileSrc(p);
      return `<button class="ph" data-ph="${i}" aria-label="${esc(g+' photo, '+p.dmg)}">${s?`<img src="${esc(s)}" alt="" loading="lazy">`:''}<span class="tag">${esc(p.phase!=='Inspection'?p.phase:p.dmg)}${p.marks?.length?' · '+p.marks.length:''}</span>${p.asset||!S.assets?'':'<span class="q">Local</span>'}${p.rep===false?'<span class="nrep">Hidden</span>':''}</button>`}).join('')}</div></div>`).join('')
      :'<span class="muted">No photos yet. Photos you take here stay in Ridgeline, not your camera roll.</span>'}`;

  // roof
  const roof=`<div class="grid2">${inp('roof.age','Roof age (yrs)',l,'number','','inputmode="numeric"')}${sel('roof.material','Material',l,['','Architectural shingle','3-tab shingle','Metal','Tile','Flat / TPO','Wood shake','Other'])}</div>
    <div class="grid2">${sel('roof.condition','Condition',l,['','Good','Fair','Worn','Failing'])}${inp('roof.layers','Layers',l,'number','1','inputmode="numeric"')}</div>
    <div class="calc"><div class="row"><span class="label grow">Roof calculator</span><span class="muted" style="font-size:12px">footprint × pitch × waste</span></div>
      <div class="grid3">${inp('roof.calc.len','Length ft',l,'text','','inputmode="decimal"')}${inp('roof.calc.wid','Width ft',l,'text','','inputmode="decimal"')}${inp('roof.calc.area','Or sq ft',l,'text','','inputmode="decimal"')}</div>
      <div class="grid3">${sel('roof.calc.pitch','Pitch',l,Array.from({length:15},(_,i)=>[String(i),i+'/12']))}${sel('roof.calc.cx','Complexity',l,[['simple','Gable · 10%'],['hip','Hip · 15%'],['cut','Cut-up · 20%']])}${inp('roof.calc.waste','Waste %',l,'text','auto','inputmode="decimal"')}</div>
      <div class="calc-out"><span class="muted" id="calcarea">${esc(calcText(l))}</span><b class="num" id="calcsq">${roofCalc(l).sq?roofCalc(l).sq.toFixed(1)+' SQ':'—'}</b></div>
      <div class="btns"><button class="btn sm" data-act="applycalc">Apply squares &amp; pitch to this roof</button><button class="btn sm" data-act="pitchgauge">📐 Measure pitch</button></div></div>
    <div class="grid3">${inp('roof.squares','Squares',l,'number','','inputmode="decimal"')}${inp('roof.pitch','Pitch',l,'text','6/12')}${inp('roof.facets','Facets',l,'number','','inputmode="numeric"')}</div>
    ${ta('findings','Inspection findings',l,'Hits per test square, soft metal damage, creased tabs, granule loss…')}
    <div><div class="label" style="margin-bottom:6px">Measurement reports & documents</div>
      ${l.docs.length?`<div class="list card" style="margin-bottom:8px">${l.docs.map((d,i)=>`<div class="li" style="cursor:default"><span class="grow trunc">${d.asset?`<a href="/_blob/${esc(d.asset)}" target="_blank" rel="noopener">${esc(d.name)}</a>`:esc(d.name)+' <span class="muted">(waiting to back up)</span>'}<span class="t2" style="display:block">${fmtStamp(d.t)}</span></span><button class="btn sm dng" data-deldoc="${i}">Remove</button></div>`).join('')}</div>`:''}
      <div class="btns"><label class="btn sm" style="position:relative">Attach PDF or image<input type="file" accept="application/pdf,image/*" data-doc style="position:absolute;inset:0;opacity:0;width:100%"></label>
      <a class="btn sm" href="https://roofr.com" target="_blank" rel="noopener">Order measurements</a></div></div>`;

  // insurance & storm
  const storms=l.storms.map((s,i)=>`<div class="card pad" style="background:var(--bg);display:flex;flex-direction:column;gap:8px">
      <div class="grid2"><label class="field"><span>Storm date</span><input type="date" data-storm="${i}" data-k="date" id="st-${i}-date" value="${esc(s.date||'')}"></label>
      <label class="field"><span>Hail size (in)</span><input type="text" inputmode="decimal" data-storm="${i}" data-k="hail" id="st-${i}-hail" value="${esc(s.hail||'')}" placeholder="None reported"></label></div>
      <div class="grid2"><label class="field"><span>Wind (mph)</span><input type="text" inputmode="numeric" data-storm="${i}" data-k="wind" id="st-${i}-wind" value="${esc(s.wind||'')}" placeholder="None reported"></label>
      <label class="field"><span>Source</span><input type="text" data-storm="${i}" data-k="src" id="st-${i}-src" value="${esc(s.src||'')}" placeholder="Where it came from"></label></div>
      <div class="row" style="justify-content:space-between;flex-wrap:wrap"><div class="chips">
        <button class="chip plain" data-stormv="${i}" data-v="0" aria-pressed="${!s.verified}">Reported only</button>
        <button class="chip" style="--c:var(--ok)" data-stormv="${i}" data-v="1" aria-pressed="${!!s.verified}"><span class="sw"></span>Damage verified on roof</button></div>
        <button class="btn sm dng" data-delstorm="${i}">Remove</button></div></div>`).join('');
  const ins=`<div class="grid2">${inp('ins.carrier','Insurance carrier',l)}${inp('ins.claim','Claim #',l)}</div>
    <div class="grid2">${inp('ins.adjuster','Adjuster',l)}${inp('ins.adjPhone','Adjuster phone',l,'tel')}</div>
    <div class="grid2">${inp('ins.dol','Date of loss',l,'date')}${inp('ins.meet','Adjuster meeting',l,'datetime-local')}</div>
    <div class="label">Storms for this address</div>${storms||'<span class="muted">No storms logged.</span>'}
    <div class="btns"><button class="btn sm pri" data-sx="lead">Find storms near this house</button><button class="btn sm" data-act="addstorm">+ Add storm</button>
      <a class="btn sm" target="_blank" rel="noopener" href="https://www.ncdc.noaa.gov/stormevents/">NOAA storm events</a>
      <a class="btn sm" target="_blank" rel="noopener" href="https://www.spc.noaa.gov/climo/reports/">SPC daily reports</a></div>`;

  // estimate
  const tot=estTotal(l);
  const est=`${l.est.lines.length?`<div class="est-line label" style="font-size:11px"><span>Item</span><span>Qty</span><span>Price</span><span></span></div>`:''}
    ${l.est.lines.map((x,i)=>`<div class="est-line"><input type="text" data-line="${i}" data-k="d" id="el-${i}-d" value="${esc(x.d)}" aria-label="Item"><input type="text" inputmode="decimal" data-line="${i}" data-k="q" id="el-${i}-q" value="${esc(x.q)}" aria-label="Quantity" placeholder="${esc(x.u||'')}"><input type="text" inputmode="decimal" data-line="${i}" data-k="p" id="el-${i}-p" value="${esc(x.p)}" aria-label="Unit price"><button class="iconbtn" data-delline="${i}" aria-label="Remove line">✕</button></div>`).join('')}
    <div class="row" style="flex-wrap:wrap;gap:8px"><select id="preset" aria-label="Add line item" style="width:auto;flex:1;min-width:180px"><option value="">Add line item…</option>${PRESETS.map((p,i)=>`<option value="${i}">${esc(p.d)} (${p.u})</option>`).join('')}<option value="custom">Custom line</option></select>
      ${num(l.roof.squares)?`<span class="muted" style="font-size:13px">${esc(l.roof.squares)} SQ measured</span>`:''}</div>
    <div class="est-tot"><span>Total</span><span class="num" id="esttot">${money2(tot)}</span></div>
    ${ta('est.notes','Scope notes',l,'Colors, upgrades, exclusions')}
    <div class="label">Homeowner signature</div>
    ${l.est.sig?`<img class="sig-img" src="${esc(fileSrc(l.est.sig))}" alt="Homeowner signature"><div class="muted" style="font-size:13.5px">Signed by ${esc(l.est.sigName||'homeowner')} · ${esc(fmtStamp(l.est.sigAt))}</div><div><button class="btn sm dng" data-act="clearsig">Clear signature</button></div>`
      :`<p class="muted" style="font-size:13px;margin:0">${esc(S.settings.terms)}</p><canvas id="sigpad" class="sig" aria-label="Signature pad"></canvas>
      <div class="grid2"><label class="field"><span>Signer name</span><input type="text" id="signame" value="${esc(l.name)}"></label><div class="field"><span>&nbsp;</span><div class="btns"><button class="btn sm" data-act="sigclear">Redo</button><button class="btn sm pri" data-act="sigsave">Accept signature</button></div></div></div>`}`;

  // sale
  const base=num(l.sale.value)+num(l.sale.upgrades)+num(l.sale.supplements);
  const sale=`<div class="chips">${JOBTYPES.map(t=>`<button class="chip plain" data-jobtype="${t}" aria-pressed="${l.sale.type===t}">${t}</button>`).join('')}</div>
    <div class="grid3">${inp('sale.value','Contract $',l,'text','','inputmode="decimal"')}${inp('sale.upgrades','Upgrades $',l,'text','','inputmode="decimal"')}${inp('sale.supplements','Supplements $',l,'text','','inputmode="decimal"')}</div>
    ${tot?`<div><button class="btn sm" data-act="useest">Use estimate total (${money(tot)})</button></div>`:''}
    <div class="grid2">${inp('sale.soldAt','Date sold',l,'date')}${sel('sale.stage','Job stage',l,['',...STAGES])}</div>
    <div class="grid2">${inp('sale.rate','Commission % (blank = '+typeRate(l.sale.type,l.origin)+'% '+l.sale.type.toLowerCase()+' rate)',l,'text',String(typeRate(l.sale.type,l.origin)),'inputmode="decimal"')}${inp('sale.commOverride','Or flat $ amount',l,'text','','inputmode="decimal"')}</div>
    <div class="card pad" style="background:var(--bg)"><div class="row"><span class="grow"><span class="label">Your commission</span><div style="font-family:var(--f-disp);font-size:30px;font-weight:700" class="num" id="commout">${money(commission(l))}</div><span class="muted" style="font-size:13px">on ${money(base)} total</span></span></div></div>
    <div class="chips" role="group" aria-label="Commission status">${[['none','Not sold'],['pending','Pending'],['earned','Earned, unpaid'],['paid','Paid']].map(([k,t])=>`<button class="chip plain" data-cs="${k}" aria-pressed="${l.sale.cstatus===k}">${t}</button>`).join('')}</div>
    ${l.sale.cstatus==='paid'?inp('sale.paidAt','Date paid',l,'date'):''}`;

  const exBanner=l.example?`<div class="banner">This is an <b>example</b> lead. Remove it from Settings → Remove sample street.</div>`:'';
  return hdr+`<div class="sheet-body gut stack">
    ${exBanner}${companyBar(l)}
    <div><h1>${esc(l.name||addr(l))}</h1><div class="muted" style="margin-top:3px">${esc(l.name?fullAddr(l):(l.city||''))}</div></div>
    ${statusChips}${qa}
    ${sec('fu','Follow-up',fuBody,os,true,l.followAt?`<span class="when ${late?'late':''}" style="margin-left:8px">${esc(fmtWhen(l.followAt))}</span>`:'')}
    ${sec('contact','Homeowner',contact,os,!l.name)}
    ${sec('notes','Notes & history',notes,os,false,`<span class="muted num" style="margin-left:6px">${hist.length}</span>`)}
    ${isCompany()?sec('thread','Conversation',threadHTML(l),os,!!(S.threadCache['lead:'+l.id]||[]).length,`<span class="muted num" style="margin-left:6px">${(S.threadCache['lead:'+l.id]||[]).length||''}</span>`):''}
    ${sec('photos','Inspection photos',photos,os,true,`<span class="muted num" style="margin-left:6px">${l.photos.length}</span>`)}
    ${sec('roof','Roof & measurements',roof,os,false)}
    ${sec('ins','Insurance & storm',ins,os,false)}
    ${sec('est','Estimate & signature',est,os,false,tot?`<span class="muted num" style="margin-left:6px">${money(tot)}</span>`:'')}
    ${sec('sale','Sale & commission',sale,os,l.status==='Sold',l.sale.cstatus!=='none'?`<span class="muted num" style="margin-left:6px">${money(commission(l))}</span>`:'')}
    <div class="btns" style="justify-content:space-between"><button class="btn" data-act="share">Copy summary for office</button><button class="btn dng" data-act="dellead">Delete lead</button></div>
  </div>`}

/* ---------- signature ---------- */
function initSig(c){const r=c.getBoundingClientRect(),dpr=window.devicePixelRatio||1;c.width=r.width*dpr;c.height=r.height*dpr;
  const x=c.getContext('2d');x.scale(dpr,dpr);x.lineWidth=2.4;x.lineCap='round';x.strokeStyle='#111';let down=false;c._ink=false;
  const pt=e=>{const b=c.getBoundingClientRect();return[e.clientX-b.left,e.clientY-b.top]};
  c.onpointerdown=e=>{down=true;c.setPointerCapture(e.pointerId);const[a,b]=pt(e);x.beginPath();x.moveTo(a,b)};
  c.onpointermove=e=>{if(!down)return;const[a,b]=pt(e);x.lineTo(a,b);x.stroke();c._ink=true};
  c.onpointerup=c.onpointercancel=()=>down=false}

/* ---------- image processing ---------- */
async function downscale(file,max=1800){
  let src;try{src=await createImageBitmap(file,{imageOrientation:'from-image'})}catch(e){
    src=await new Promise((res,rej)=>{const i=new Image();i.onload=()=>res(i);i.onerror=rej;i.src=URL.createObjectURL(file)})}
  const w=src.width,h=src.height,k=Math.min(1,max/Math.max(w,h));const c=document.createElement('canvas');c.width=Math.round(w*k);c.height=Math.round(h*k);
  c.getContext('2d').drawImage(src,0,0,c.width,c.height);
  return await new Promise(r=>c.toBlob(r,'image/jpeg',.84))}
async function storeLocal(blob){const id='f'+rid();try{await idbPut(id,blob)}catch(e){}S.urls.set(id,URL.createObjectURL(blob));return id}

async function addPhotos(files){const l=S.leads.get(S.open);if(!l||!files.length)return;
  const slope=$('#newslope')?.value||S.lastSlope;S.lastSlope=slope;toast(files.length>1?`Saving ${files.length} photos…`:'Saving photo…');
  let first=null;
  for(const f of files){try{const b=await downscale(f);const id=await storeLocal(b);
    l.photos.push({id,asset:null,t:Date.now(),slope,dmg:'Hail',cap:'',phase:'Inspection',marks:[],rep:true});if(first==null)first=l.photos.length-1}catch(e){toast('Could not read that image')}}
  saveLead(l);renderSheet();uploadPending();
  if(files.length===1&&first!=null)openAnn(first)}
async function addDoc(file){const l=S.leads.get(S.open);if(!l||!file)return;
  let b=file;if(file.type.startsWith('image/'))b=await downscale(file,2400);
  if(!['application/pdf','image/jpeg','image/png','image/webp'].includes(b.type)){toast('Attach a PDF or a photo');return}
  const id=await storeLocal(b);l.docs.push({id,asset:null,name:file.name||'Document',t:Date.now()});saveLead(l);renderSheet();uploadPending()}

/* ---------- annotate ---------- */
let ANN={i:0,mark:'Hail'};
function openAnn(i){ANN.i=i;renderAnn()}
function renderAnn(){const l=S.leads.get(S.open);const p=l&&l.photos[ANN.i];if(!p){$('#layer .ann')?.remove();return}
  let el=$('#layer .ann');if(!el){el=document.createElement('div');el.className='ann';el.setAttribute('role','dialog');el.setAttribute('aria-modal','true');$('#layer').appendChild(el)}
  const mc=k=>(MARKS.find(m=>m.k===k)||MARKS[2]).c;
  el.innerHTML=`<div class="ann-top"><button class="iconbtn" data-act="annclose" aria-label="Done"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg></button>
    <div class="grow" style="font-weight:600">${esc(p.slope)} <span class="muted" style="font-weight:400;font-size:13px;color:#9AA7B3">· ${fmtStamp(p.t)}</span></div>
    <span style="font-size:13px;color:#9AA7B3" class="num">${ANN.i+1} / ${l.photos.length}</span>
    <button class="iconbtn" data-act="annprev" aria-label="Previous photo">‹</button><button class="iconbtn" data-act="annnext" aria-label="Next photo">›</button></div>
  <div class="ann-stage"><div class="ann-wrap" id="annwrap"><img src="${esc(fileSrc(p))}" alt="${esc(p.cap||p.slope)}" draggable="false">
    ${(p.marks||[]).map(m=>`<span class="mark" style="left:${m.x}%;top:${m.y}%;--mc:${mc(m.k)}"><i>${esc(m.k)}</i></span>`).join('')}</div></div>
  <div class="ann-tools">
    <div class="row" style="flex-wrap:wrap;gap:8px"><span class="muted" style="font-size:13px">Tap photo to mark:</span>${MARKS.map(m=>`<button class="chip" style="--c:${m.c}" data-mk="${m.k}" aria-pressed="${ANN.mark===m.k}"><span class="sw"></span>${m.k}</button>`).join('')}
      <button class="btn sm" data-act="annundo" ${p.marks?.length?'':'disabled'}>Undo mark</button></div>
    <div class="grid2"><label class="field"><span class="muted">Slope</span><select data-pf="slope" id="pf-slope">${SLOPES.map(s=>`<option ${s===p.slope?'selected':''}>${s}</option>`).join('')}</select></label>
      <label class="field"><span class="muted">Damage</span><select data-pf="dmg" id="pf-dmg">${DMG.map(s=>`<option ${s===p.dmg?'selected':''}>${s}</option>`).join('')}</select></label></div>
    <div class="chips">${PHASES.map(s=>`<button class="chip plain" data-phase="${s}" aria-pressed="${p.phase===s}">${s}</button>`).join('')}
      <button class="chip plain" data-act="togrep" aria-pressed="${p.rep!==false}">In report</button></div>
    <label class="field"><span class="muted">Caption</span><input type="text" data-pf="cap" id="pf-cap" value="${esc(p.cap)}" placeholder="8 hits in 10×10 test square"></label>
    <div class="btns" style="justify-content:space-between"><button class="btn sm dng" data-act="delphoto">Delete photo</button><button class="btn sm pri" data-act="annclose">Done</button></div>
  </div>`;
  $('#annwrap img',el).onclick=e=>{const b=e.target.getBoundingClientRect();const x=+((e.clientX-b.left)/b.width*100).toFixed(1),y=+((e.clientY-b.top)/b.height*100).toFixed(1);
    p.marks=p.marks||[];p.marks.push({x,y,k:ANN.mark});saveLead(l,{quiet:true});renderAnn()};
}

/* ---------- modals ---------- */
function modal(html,cls=''){const m=document.createElement('div');m.className='modal';m.innerHTML=`<div class="modal-card ${cls}" role="dialog" aria-modal="true">${html}</div>`;
  m.addEventListener('click',e=>{if(e.target===m)m.remove()});$('#layer').appendChild(m);return m}
function confirmBox(msg,ok='Delete'){return new Promise(res=>{const m=modal(`<h2>Are you sure?</h2><p style="margin:0">${esc(msg)}</p><div class="btns" style="justify-content:flex-end"><button class="btn" data-c="0">Cancel</button><button class="btn pri" data-c="1" style="background:var(--danger);border-color:var(--danger);color:#fff">${esc(ok)}</button></div>`);
  m.addEventListener('click',e=>{const b=e.target.closest('[data-c]');if(b){m.remove();res(b.dataset.c==='1')}})})}

function knockModal(pre={}){
  let result=pre.result||'';quickPos();
  const m=modal(`<div class="row"><h2 class="grow">Log a door</h2><button class="iconbtn" data-c="x" aria-label="Close">✕</button></div>
    <div class="grid2" style="grid-template-columns:110px 1fr">
      <label class="field"><span>House #</span><input type="text" inputmode="numeric" id="k-num" value="${esc(pre.num||'')}" autocomplete="off"></label>
      <label class="field"><span>Street</span><input type="text" id="k-street" list="k-streets" value="${esc(pre.street??S.lastStreet)}" autocomplete="off"></label></div>
    <datalist id="k-streets">${streetsData().map(s=>`<option value="${esc(s.name)}">`).join('')}</datalist>
    <label class="field"><span>Name (optional)</span><input type="text" id="k-name" autocomplete="off"></label>
    <div><div class="label" style="margin-bottom:8px">What happened?</div><div class="chips" id="k-res">${KNOCK_RESULTS.map(k=>`<button class="chip" style="--c:${sv(k)}" data-r="${esc(k)}" aria-pressed="false"><span class="sw"></span>${esc(k)}</button>`).join('')}</div></div>
    <div class="btns"><button class="btn pri grow" data-c="save">Save</button><button class="btn" data-c="next" title="Save and move two doors down the same side">Save + next door</button></div>
    <p class="muted" style="font-size:12.5px;margin:0">“Next door” saves and jumps the house number by 2, same side of the street.</p>`);
  setTimeout(()=>$(pre.num?'#k-name':'#k-num',m)?.focus(),60);
  m.addEventListener('click',e=>{const r=e.target.closest('[data-r]');if(r){result=r.dataset.r;$$('#k-res .chip',m).forEach(b=>b.setAttribute('aria-pressed',b===r));return}
    const c=e.target.closest('[data-c]');if(!c)return;
    if(c.dataset.c==='x'){m.remove();return}
    const n=$('#k-num',m).value.trim(),st=$('#k-street',m).value.trim(),nm=$('#k-name',m).value.trim();
    if(!n&&!st){toast('Add a house number and street');return}
    if(!result){toast('Pick what happened at the door');return}
    S.lastStreet=st;
    let l=leadsArr().find(x=>streetKey(x.street)===streetKey(st)&&String(x.num).trim()===n);
    if(!l)l=newLead({num:n,street:st,city:pre.city||S.settings.city||''});
    if(nm&&!l.name)l.name=nm;
    if(pre.geo&&!l.geo)l.geo=pre.geo;
    if(l.status!==result){setStatus(l,result);l.knocks.at(-1).d=1}else l.knocks.push({t:Date.now(),r:result,d:1,...stamp()});
    if(!l._saved&&MV.gps.pos){l.pinned_lat=+MV.gps.pos.lat.toFixed(6);l.pinned_lng=+MV.gps.pos.lng.toFixed(6)}
    saveLead(l);m.remove();render();checkStreak();
    if(c.dataset.c==='next'){const nn=parseInt(n,10);knockModal({num:isFinite(nn)?String(nn+2):'',street:st,city:pre.city,pin:pre.pin?{...pre.pin,t:Math.min(.98,+(pre.pin.t+.07).toFixed(3))}:null});toast(`${addr(l)} saved`)}
    else if(['Follow Up','Inspection Scheduled','Inspected','Claim Pending','Sold'].includes(result)){openLead(l.id);toast('Saved — set the follow-up')}
    else toast(`${addr(l)} · ${result}`)});
}

/* ---------- export ---------- */
const MIME={csv:'text/csv',json:'application/json',html:'text/html',pdf:'application/pdf'};
async function localSave({filename,data}){const ext=filename.split('.').pop().toLowerCase();
  const blob=data instanceof Blob?data:new Blob([data],{type:MIME[ext]||'application/octet-stream'});
  const file=new File([blob],filename,{type:blob.type||MIME[ext]||''});
  if(navigator.canShare&&navigator.canShare({files:[file]})){try{await navigator.share({files:[file],title:filename});return{status:'saved'}}catch(e){throw{code:e&&e.name==='AbortError'?'declined':'unavailable',message:e&&e.message}}}
  const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=filename;document.body.appendChild(a);a.click();setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove()},1500);return{status:'saved'}}
async function save(filename,data){if(!S.dl){toast('Downloads aren’t available here');return}
  try{await S.dl.save({filename,data});toast('Saved')}catch(e){if(e&&e.code!=='declined')toast('Could not save: '+(e.message||e.code))}}
function exportCSV(){const cols=['Status','Name','House #','Street','City','Phone','Email','Source','First contact','Follow-up','Roof age','Material','Squares','Pitch','Carrier','Claim #','Adjuster','Job type','Contract','Upgrades','Supplements','Commission','Commission status','Date sold','Stage','Photos','Last note'];
  const q=v=>{v=String(v??'');return /[",\n]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v};
  const rows=leadsArr().map(l=>[l.status,l.name,l.num,l.street,l.city,l.phone,l.email,l.source,fmtDate(l.created),l.followAt,l.roof.age,l.roof.material,l.roof.squares,l.roof.pitch,l.ins.carrier,l.ins.claim,l.ins.adjuster,l.sale.type,l.sale.value,l.sale.upgrades,l.sale.supplements,commission(l).toFixed(2),l.sale.cstatus,l.sale.soldAt,l.sale.stage,l.photos.length,(l.log.at(-1)||{}).text||'']);
  save(`ridgeline-leads-${todayKey()}.csv`,[cols,...rows].map(r=>r.map(q).join(',')).join('\n'))}
async function blobToData(b){return await new Promise(r=>{const f=new FileReader();f.onload=()=>r(f.result);f.onerror=()=>r('');f.readAsDataURL(b)})}
async function exportJSON(){toast('Packing backup…');const leads=clone(leadsArr());
  for(const l of leads)for(const f of [...l.photos,...l.docs,...(l.est.sig?[l.est.sig]:[])]){if(f.asset)continue;try{const b=await idbGet(f.id);if(b)f.data=await blobToData(b)}catch(e){}}
  S.settings.lastBackup=Date.now();saveSettings();
  save(`ridgeline-backup-${todayKey()}.json`,new Blob([JSON.stringify({app:'Ridgeline',exported:new Date().toISOString(),settings:S.settings,leads})],{type:'application/json'}))}

function loadScript(src){return new Promise(res=>{const t=document.createElement('script');t.src=src;t.onload=()=>res(true);t.onerror=()=>{t.remove();res(false)};document.head.appendChild(t)})}
async function ensureJsPDF(){if(window.jspdf)return true;
  for(const src of ['vendor/jspdf.umd.min.js','https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js','https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js']){if(await loadScript(src)&&window.jspdf)return true}return !!window.jspdf}
/* ---------- inspection report as a PDF ---------- */
function loadImg(src){return new Promise(res=>{if(!src)return res(null);const i=new Image();i.onload=()=>res(i);i.onerror=()=>res(null);i.src=src})}
async function pdfCover(doc,l,ph,{W,H,M,CW,ACC,INK,MUT,clean}){const s=S.settings;const heroH=Math.round(H*.5);
  const hero=ph.find(p=>p.marks&&p.marks.length)||ph[0];const img=hero?await loadImg(await toDataURL(fileSrc(hero))):null;
  if(img){const ar=W/heroH,iw=img.naturalWidth,ih=img.naturalHeight;let sw=iw,sh=iw/ar;if(sh>ih){sh=ih;sw=ih*ar}
    const c=document.createElement('canvas');c.width=1300;c.height=Math.round(1300/ar);c.getContext('2d').drawImage(img,(iw-sw)/2,(ih-sh)/2,sw,sh,0,0,c.width,c.height);
    doc.addImage(c.toDataURL('image/jpeg',.72),'JPEG',0,0,W,heroH,'cover-hero')}
  else{doc.setFillColor(20,25,34);doc.rect(0,0,W,heroH,'F');doc.setDrawColor(...ACC);doc.setLineWidth(14);doc.setLineCap('round');doc.setLineJoin('round');
    const cx=W/2,cy=heroH/2;doc.lines([[150,-110],[150,110]],cx-150,cy+50,[1,1],'S',false);
    doc.setDrawColor(255,255,255);doc.setLineWidth(10);doc.lines([[0,90],[200,0],[0,-90]],cx-100,cy+30,[1,1],'S',false)}
  doc.setFillColor(...ACC);doc.rect(0,heroH,W,7,'F');
  if(s.company){doc.setFont('helvetica','bold');doc.setFontSize(11);const t=clean(s.company),tw=doc.getTextWidth(t);
    doc.setFillColor(255,255,255);doc.roundedRect(M-4,M-8,tw+28,28,7,7,'F');doc.setFillColor(...ACC);doc.circle(M+8,M+6,3.2,'F');doc.setTextColor(...INK);doc.text(t,M+16,M+10)}
  let y=heroH+7+46;
  doc.setFont('helvetica','bold');doc.setFontSize(10.5);doc.setTextColor(...ACC);doc.text('ROOF INSPECTION REPORT',M,y,{charSpace:1.6});y+=36;
  doc.setFontSize(30);doc.setTextColor(...INK);const a1=doc.splitTextToSize(clean(addr(l)),CW).slice(0,2);doc.text(a1,M,y);y+=a1.length*33-6;
  if(l.city){doc.setFont('helvetica','normal');doc.setFontSize(15);doc.setTextColor(...MUT);doc.text(clean(l.city),M,y+18);y+=26}
  y+=20;doc.setFontSize(11);
  const meta=[l.name?['Prepared for',l.name]:null,['Inspection date',fmtDate(Date.now())],l.ins.carrier?['Insurance',l.ins.carrier+(l.ins.claim?' · Claim '+l.ins.claim:'')]:null].filter(Boolean);
  for(const [k,v] of meta){doc.setFont('helvetica','normal');doc.setTextColor(...MUT);doc.text(clean(k),M,y);doc.setFont('helvetica','bold');doc.setTextColor(...INK);doc.text(doc.splitTextToSize(clean(v),CW-110)[0],M+110,y);y+=18}
  const hail=l.storms.reduce((a,x)=>Math.max(a,num(x.hail)),0),ver=l.storms.filter(x=>x.verified).length;
  const stats=[['ROOF',[l.roof.material,l.roof.age?l.roof.age+' yrs':''].filter(Boolean).join(' · ')||'—'],
    ['STORMS',l.storms.length?l.storms.length+(hail?` · up to ${hail}" hail`:''):'None logged'],
    ['DAMAGE',ver?`Verified on roof`:ph.some(p=>p.marks&&p.marks.length)?'Marked in photos':'See findings'],
    ['PHOTOS',String(ph.length)]];
  const bh=58,by=H-M-bh-24,gap=10,bw=(CW-gap*3)/4;
  stats.forEach(([k,v],i)=>{const x=M+i*(bw+gap);doc.setFillColor(244,245,247);doc.roundedRect(x,by,bw,bh,8,8,'F');
    doc.setFont('helvetica','bold');doc.setFontSize(7.5);doc.setTextColor(...MUT);doc.text(k,x+11,by+19,{charSpace:1});
    doc.setFontSize(11.5);doc.setTextColor(...INK);const vl=doc.splitTextToSize(clean(v),bw-20).slice(0,2);doc.text(vl,x+11,by+36)});
  const prep=[s.repName,s.repPhone].filter(Boolean).map(clean).join(' · ');
  if(prep){doc.setFont('helvetica','normal');doc.setFontSize(9.5);doc.setTextColor(...MUT);doc.text('Prepared by '+prep,M,H-M+2)}
  if(s.company){doc.setFont('helvetica','bold');doc.setFontSize(9.5);doc.setTextColor(...INK);doc.text(clean(s.company),W-M,H-M+2,{align:'right'})}}
async function reportPDF(l){
  const {jsPDF}=window.jspdf;const doc=new jsPDF({unit:'pt',format:'letter',compress:true});
  const W=612,H=792,M=40,CW=W-2*M;let y=M;const s=S.settings;
  const ACC=hexRgb(accentPair()[0])||[242,84,27],INK=[26,26,26],MUT=[110,110,110],LINE=[226,226,226];
  const clean=t=>String(t??'').replace(/[^\x20-\x7E -ÿ–—‘’“”•…]/g,'');
  const ensure=h=>{if(y+h>H-M-18){doc.addPage();y=M}};
  const head=t=>{ensure(40);y+=10;doc.setFont('helvetica','bold');doc.setFontSize(13);doc.setTextColor(...INK);doc.text(clean(t),M,y+12);y+=18;doc.setDrawColor(...INK);doc.setLineWidth(1.2);doc.line(M,y,M+CW,y);y+=12};
  const para=(t,size=10.5,color=INK,style='normal')=>{doc.setFont('helvetica',style);doc.setFontSize(size);doc.setTextColor(...color);
    for(const ln of doc.splitTextToSize(clean(t),CW)){ensure(size+4);doc.text(ln,M,y+size);y+=size+4}};
  const rows=pairs=>{for(const [k,v] of pairs){if(!v)continue;doc.setFontSize(10.5);const lines=doc.splitTextToSize(clean(v),CW-150);ensure(lines.length*15+2);
      doc.setFont('helvetica','normal');doc.setTextColor(...MUT);doc.text(clean(k),M,y+11);doc.setTextColor(...INK);doc.text(lines,M+150,y+11);y+=lines.length*15+2}};
  const phC=l.photos.filter(p=>p.rep!==false);
  doc.setProperties({title:clean('Roof Inspection Report - '+fullAddr(l)),subject:'Roof inspection report',author:clean(s.repName||s.company||''),creator:'Ridgeline'});
  await pdfCover(doc,l,phC,{W,H,M,CW,ACC,INK,MUT,clean});doc.addPage();y=M;
  // header
  doc.setFont('helvetica','bold');doc.setFontSize(22);doc.setTextColor(...INK);doc.text('Roof Inspection Report',M,y+20);
  doc.setFont('helvetica','normal');doc.setFontSize(10.5);doc.setTextColor(...MUT);doc.text(fmtDate(Date.now()),M,y+38);
  const right=[s.company,s.repName,s.repPhone].filter(Boolean).map(clean);
  right.forEach((t,i)=>{doc.setFont('helvetica',i===0&&s.company?'bold':'normal');doc.setTextColor(...(i===0?INK:MUT));doc.text(t,W-M,y+14+i*14,{align:'right'})});
  y+=Math.max(52,18+right.length*14);doc.setDrawColor(...ACC);doc.setLineWidth(3);doc.line(M,y,M+CW,y);y+=8;
  head('Property');
  rows([['Homeowner',l.name],['Address',fullAddr(l)],['Roof material',l.roof.material],['Roof age',l.roof.age?l.roof.age+' years':''],['Condition',l.roof.condition],['Size',l.roof.squares?l.roof.squares+' squares':''],['Pitch',l.roof.pitch],['Facets',l.roof.facets],['Layers',l.roof.layers]]);
  if(l.ins.carrier||l.ins.claim){head('Insurance');rows([['Carrier',l.ins.carrier],['Claim #',l.ins.claim],['Date of loss',l.ins.dol?fmtDate(l.ins.dol+'T12:00'):''],['Adjuster',l.ins.adjuster]])}
  if(l.storms.length){head('Storm activity');
    for(const st of l.storms){ensure(34);doc.setFont('helvetica','bold');doc.setFontSize(10.5);doc.setTextColor(...INK);
      const desc=[st.date?fmtDate(st.date+'T12:00'):'Date not set',[st.hail?st.hail+'" hail':'',st.wind?st.wind+' mph wind':''].filter(Boolean).join(', '),st.src?'source: '+st.src:''].filter(Boolean).join('  •  ');
      doc.text(clean(desc),M,y+11);
      const tag=st.verified?'DAMAGE VERIFIED ON ROOF':'REPORTED IN AREA — NOT VERIFIED';doc.setFontSize(8.5);const tw=doc.getTextWidth(tag)+12;
      doc.setFillColor(...(st.verified?[21,128,61]:[107,114,128]));doc.roundedRect(M,y+16,tw,13,3,3,'F');doc.setTextColor(255,255,255);doc.text(tag,M+6,y+25.5);y+=36}}
  if(l.findings){head('Findings');para(l.findings)}
  const ph=l.photos.filter(p=>p.rep!==false);
  if(ph.length){head(`Photos (${ph.length})`);
    const gap=14,cw=(CW-gap)/2;const items=[];
    for(const p of ph){const img=await loadImg(await toDataURL(fileSrc(p)));
      const ih=img?Math.min(cw*img.naturalHeight/img.naturalWidth,cw*1.25):cw*.75;
      doc.setFontSize(9.5);const cap=doc.splitTextToSize(clean([p.slope,p.phase!=='Inspection'?p.phase:p.dmg,p.marks&&p.marks.length?p.marks.length+' marked':''].filter(Boolean).join('  \u2022  ')),cw);
      const cap2=p.cap?doc.splitTextToSize(clean(p.cap),cw):[];items.push({p,img,ih,cap,cap2,h:ih+14+cap.length*12+cap2.length*12+12})}
    for(let i=0;i<items.length;i+=2){const pair=items.slice(i,i+2);const rowH=Math.max(...pair.map(t=>t.h))+gap;ensure(rowH);
      pair.forEach((t,k)=>{const x=M+k*(cw+gap),{p,img,ih}=t;
        if(img){const c=document.createElement('canvas');const sc=Math.min(1,1000/Math.max(img.naturalWidth,img.naturalHeight));c.width=Math.round(img.naturalWidth*sc);c.height=Math.round(img.naturalHeight*sc);c.getContext('2d').drawImage(img,0,0,c.width,c.height);
          doc.addImage(c.toDataURL('image/jpeg',.72),'JPEG',x,y,cw,ih)}else{doc.setFillColor(240,240,240);doc.rect(x,y,cw,ih,'F')}
        for(const m of p.marks||[]){const hex=(MARKS.find(q=>q.k===m.k)||MARKS[2]).c;const rgb=[1,3,5].map(j=>parseInt(hex.slice(j,j+2),16));
          doc.setDrawColor(...rgb);doc.setLineWidth(2.4);doc.circle(x+m.x/100*cw,y+m.y/100*ih,cw*.045,'S')}
        let ty=y+ih+14;doc.setFont('helvetica','bold');doc.setFontSize(9.5);doc.setTextColor(...INK);doc.text(t.cap,x,ty);ty+=t.cap.length*12;
        if(t.cap2.length){doc.setFont('helvetica','normal');doc.text(t.cap2,x,ty);ty+=t.cap2.length*12}
        doc.setFont('helvetica','normal');doc.setFontSize(8.5);doc.setTextColor(...MUT);doc.text(clean(fmtStamp(p.t)),x,ty)});
      y+=rowH}}
  if(l.est.lines.length){head('Estimate');
    const cx=[M,M+CW-200,M+CW-110,M+CW];doc.setFontSize(9);doc.setFont('helvetica','bold');doc.setTextColor(...MUT);ensure(18);
    doc.text('ITEM',cx[0],y+10);doc.text('QTY',cx[1],y+10,{align:'right'});doc.text('PRICE',cx[2],y+10,{align:'right'});doc.text('AMOUNT',cx[3],y+10,{align:'right'});y+=16;
    doc.setFont('helvetica','normal');doc.setFontSize(10);
    for(const x of l.est.lines){const d=doc.splitTextToSize(clean(x.d),CW-230);ensure(d.length*13+8);doc.setTextColor(...INK);doc.text(d,cx[0],y+10);
      doc.text(clean(`${x.q} ${x.u||''}`.trim()),cx[1],y+10,{align:'right'});doc.text(money2(num(x.p)),cx[2],y+10,{align:'right'});doc.text(money2(num(x.q)*num(x.p)),cx[3],y+10,{align:'right'});
      y+=d.length*13+4;doc.setDrawColor(...LINE);doc.setLineWidth(.6);doc.line(M,y,M+CW,y);y+=4}
    ensure(22);doc.setFont('helvetica','bold');doc.setFontSize(12);doc.setTextColor(...INK);doc.text('Total',cx[2],y+14,{align:'right'});doc.text(money2(estTotal(l)),cx[3],y+14,{align:'right'});y+=24;
    if(l.est.notes)para(l.est.notes,10)}
  if(l.est.sig){head('Authorization');para(s.terms||'',9,MUT);const img=await loadImg(await toDataURL(fileSrc(l.est.sig)));
    if(img){const w=200,h=Math.min(90,w*img.naturalHeight/img.naturalWidth);ensure(h+30);doc.addImage(img,'PNG',M,y+4,w,h);y+=h+6;doc.setDrawColor(150,150,150);doc.setLineWidth(.8);doc.line(M,y,M+260,y)}
    y+=4;para(`${l.est.sigName||''}  •  ${fmtStamp(l.est.sigAt)}`,9.5,INK)}
  y+=8;para('Storm data marked "reported" comes from public weather reports for the area and does not by itself confirm damage to this roof.',8.5,MUT);
  const n=doc.getNumberOfPages();for(let i=2;i<=n;i++){doc.setPage(i);doc.setFont('helvetica','normal');doc.setFontSize(8.5);doc.setTextColor(...MUT);
    doc.text(clean(fullAddr(l)),M,H-22);doc.text(`Page ${i-1} of ${n-1}`,W-M,H-22,{align:'right'})}
  return doc.output('blob')}

/* ---------- report ---------- */
async function toDataURL(src){try{const b=await (await fetch(src)).blob();return await new Promise(r=>{const f=new FileReader();f.onload=()=>r(f.result);f.onerror=()=>r('');f.readAsDataURL(b)})}catch(e){return''}}
async function reportHTML(l,embed){
  const s=S.settings;const ph=l.photos.filter(p=>p.rep!==false);
  const srcs=await Promise.all(ph.map(p=>embed?toDataURL(fileSrc(p)):Promise.resolve(fileSrc(p))));
  const sig=l.est.sig?(embed?await toDataURL(fileSrc(l.est.sig)):fileSrc(l.est.sig)):'';
  const mc=k=>(MARKS.find(m=>m.k===k)||MARKS[2]).c;
  const e=esc;const row=(k,v)=>v?`<tr><th>${e(k)}</th><td>${e(v)}</td></tr>`:'';
  const tot=estTotal(l);
  return `<div class="rp"><style>.rp{font-family:'Plus Jakarta Sans',Arial,sans-serif;color:#1a1a1a;line-height:1.45}.rp h1{font-family:'Plus Jakarta Sans',Arial,sans-serif;font-weight:800;letter-spacing:-.02em;font-size:28px;margin:0}.rp h2{font-family:'Plus Jakarta Sans',Arial,sans-serif;font-weight:800;font-size:17px;margin:22px 0 8px;border-bottom:2px solid #1a1a1a;padding-bottom:3px}
  .rp .hd{display:flex;justify-content:space-between;gap:16px;flex-wrap:wrap;border-bottom:4px solid ${accentPair()[0]};padding-bottom:12px}.rp table{border-collapse:collapse;width:100%;font-size:14px}.rp th{text-align:left;color:#555;font-weight:600;padding:4px 10px 4px 0;width:38%;vertical-align:top}.rp td{padding:4px 0}
  .rp .rp-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}.rp figure{margin:0;break-inside:avoid}.rp .pw{position:relative}.rp .pw img{width:100%;display:block;border-radius:4px}
  .rp .mk{position:absolute;width:9%;aspect-ratio:1;transform:translate(-50%,-50%);border-radius:50%;border:3px solid;box-shadow:0 0 0 1px rgba(0,0,0,.6)}.rp figcaption{font-size:12.5px;color:#333;margin-top:4px}
  .rp .tag{display:inline-block;font-size:11px;font-weight:700;padding:1px 6px;border-radius:4px;margin-right:4px;color:#fff}.rp .st{font-size:13.5px;padding:6px 0;border-bottom:1px solid #ddd}.rp .lt td,.rp .lt th{border-bottom:1px solid #e5e5e5;padding:6px 4px}.rp .lt .r{text-align:right}</style>
  <div class="hd"><div><h1>Roof Inspection Report</h1><div style="color:#555">${e(fmtDate(Date.now()))}</div></div><div style="text-align:right;font-size:14px">${s.company?`<b>${e(s.company)}</b><br>`:''}${e(s.repName)}${s.repPhone?'<br>'+e(s.repPhone):''}</div></div>
  <h2>Property</h2><table>${row('Homeowner',l.name)}${row('Address',fullAddr(l))}${row('Roof material',l.roof.material)}${row('Roof age',l.roof.age?l.roof.age+' years':'')}${row('Condition',l.roof.condition)}${row('Size',l.roof.squares?l.roof.squares+' squares':'')}${row('Pitch',l.roof.pitch)}${row('Facets',l.roof.facets)}${row('Layers',l.roof.layers)}</table>
  ${l.ins.carrier||l.ins.claim?`<h2>Insurance</h2><table>${row('Carrier',l.ins.carrier)}${row('Claim #',l.ins.claim)}${row('Date of loss',l.ins.dol?fmtDate(l.ins.dol+'T12:00'):'')}${row('Adjuster',l.ins.adjuster)}</table>`:''}
  ${l.storms.length?`<h2>Storm activity</h2>${l.storms.map(st=>`<div class="st"><b>${e(st.date?fmtDate(st.date+'T12:00'):'Date not set')}</b> — ${st.hail?e(st.hail)+'" hail':''}${st.hail&&st.wind?', ':''}${st.wind?e(st.wind)+' mph wind':''}${st.src?' · source: '+e(st.src):''}<br><span class="tag" style="background:${st.verified?'#15803D':'#6B7280'}">${st.verified?'DAMAGE VERIFIED ON ROOF':'REPORTED IN AREA — NOT VERIFIED'}</span></div>`).join('')}`:''}
  ${l.findings?`<h2>Findings</h2><p style="white-space:pre-wrap;margin:0">${e(l.findings)}</p>`:''}
  ${ph.length?`<h2>Photos (${ph.length})</h2><div class="rp-grid">${ph.map((p,i)=>`<figure><div class="pw"><img src="${e(srcs[i])}" alt="">${(p.marks||[]).map(m=>`<span class="mk" style="left:${m.x}%;top:${m.y}%;border-color:${mc(m.k)}"></span>`).join('')}</div>
    <figcaption><span class="tag" style="background:#333">${e(p.slope)}</span><span class="tag" style="background:${accentPair()[0]}">${e(p.phase!=='Inspection'?p.phase:p.dmg)}</span>${p.marks?.length?`${p.marks.length} marked`:''}<br>${e(p.cap)} <span style="color:#777">${e(fmtStamp(p.t))}</span></figcaption></figure>`).join('')}</div>`:''}
  ${l.est.lines.length?`<h2>Estimate</h2><table class="lt"><tr><th>Item</th><th class="r">Qty</th><th class="r">Price</th><th class="r">Amount</th></tr>${l.est.lines.map(x=>`<tr><td>${e(x.d)}</td><td class="r">${e(x.q)} ${e(x.u||'')}</td><td class="r">${money2(num(x.p))}</td><td class="r">${money2(num(x.q)*num(x.p))}</td></tr>`).join('')}<tr><th colspan="3" class="r">Total</th><td class="r"><b>${money2(tot)}</b></td></tr></table>${l.est.notes?`<p style="white-space:pre-wrap">${e(l.est.notes)}</p>`:''}`:''}
  ${sig?`<h2>Authorization</h2><p style="font-size:13px;color:#444">${e(s.terms)}</p><img src="${e(sig)}" alt="Signature" style="max-height:110px;border-bottom:1px solid #999"><div style="font-size:13px">${e(l.est.sigName)} · ${e(fmtStamp(l.est.sigAt))}</div>`:''}
  <p style="font-size:11.5px;color:#777;margin-top:24px">Storm data marked “reported” comes from public weather reports for the area and does not by itself confirm damage to this roof.</p></div>`}
async function openReport(){const l=S.leads.get(S.open);if(!l)return;await ensureUrls(leadFilePaths(l));
  const w=document.createElement('div');w.className='report-wrap';w.setAttribute('role','dialog');w.setAttribute('aria-modal','true');
  w.innerHTML=`<div class="sheet-top"><div class="row gut" style="max-width:760px;margin:0 auto;padding-block:8px"><button class="iconbtn" data-act="repclose" aria-label="Back"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg></button><div class="grow" style="font-weight:600">Inspection report</div>${S.dl?'<button class="btn sm pri" data-act="repsave">Save PDF</button>':''}</div></div>
  <div class="gut"><div class="paper">Building report…</div><p class="muted gut" style="font-size:13px;max-width:760px;margin:0 auto">Only photos marked “In report” appear. Save PDF makes a print-ready file you can text, email or save to Files.</p></div>`;
  $('#layer').appendChild(w);$('.paper',w).innerHTML=await reportHTML(l,false)}

/* ---------- events ---------- */
document.addEventListener('click',async e=>{
  const t=e.target;
  const tab=t.closest('[data-tab]');if(tab){location.hash=tab.dataset.tab;if(S.tab===tab.dataset.tab)render();return}
  const op=t.closest('[data-open]');if(op&&!t.closest('.sheet')){openLead(op.dataset.open);return}
  const sf=t.closest('[data-sf]');if(sf){S.streetF=sf.dataset.sf;render();return}
  const lf=t.closest('[data-lf]');if(lf){S.leadF=lf.dataset.lf;render();return}
  const cp=t.closest('[data-copy]');if(cp){try{await navigator.clipboard.writeText(cp.dataset.copy);toast('Copied')}catch(err){toast(cp.dataset.copy)}return}
  const fd=t.closest('[data-fudone]');if(fd){const L=S.leads.get(fd.dataset.fudone);if(L){L.fuDone=L.fuDone||[];L.fuDone.push({t:Date.now(),due:L.followAt});L.log.push({t:Date.now(),text:'Follow-up done'+(L.followAt?' (was due '+fmtWhen(L.followAt)+')':'')});L.followAt='';saveLead(L);render();if(S.open===L.id)renderSheet();toast('Follow-up done')}return}
  const kv=t.closest('[data-kv]');if(kv){S.knockView=kv.dataset.kv;render();return}
  const mm=t.closest('[data-mm]');if(mm){S.mapMode=mm.dataset.mm;S.selPin=null;S.selZone=null;if(S.mapMode!=='skip')S.zoneDraft=null;render();return}
  const mz=t.closest('[data-mz]');if(mz&&MV.map){const k=mz.dataset.mz;if(k==='in')MV.map.zoomIn();if(k==='out')MV.map.zoomOut();if(k==='gps')toggleGPS();
    if(k==='layer'){setBase({hybrid:'sat',sat:'street',street:'hybrid'}[MV.base]||'hybrid');render()}
    if(k==='storm'){S.settings.stormLayer=!S.settings.stormLayer;if(!S.settings.stormLayer)ST.sel=null;saveSettings();render();toast(S.settings.stormLayer?`Storm reports on · last ${ST_RANGES[sFilt().range][0]}`:'Storm reports off')}return}
  const rt=t.closest('[data-rt]');if(rt){routeAction(rt.dataset.rt);return}
  const rd=t.closest('[data-rtdel]');if(rd){const i=RT.ids.indexOf(rd.dataset.rtdel);if(i>=0){RT.ids.splice(i,1);if(i<RT.idx)RT.idx--;saveRoute();buildRoute({optimize:false})}return}
  if(t.closest('[data-act="openroute"]')){S.knockView='map';S.mapMode='route';if(location.hash!=='#knock')location.hash='knock';else render();return}
  if(t.closest('[data-act="planroute"]')){const n=addToRoute(dueLeadIds());S.knockView='map';S.mapMode='route';S.selPin=null;if(location.hash!=='#knock')location.hash='knock';else render();buildRoute({optimize:true});if(n)toast(`Planning ${RT.ids.length} stops`);return}
  if(t.closest('[data-act="pinme"]')&&MV.gps.pos){pinAt(L.latLng(MV.gps.pos.lat,MV.gps.pos.lng));return}
  const qs=t.closest('[data-qs]');if(qs&&S.selPin){const L=S.leads.get(S.selPin);if(L){const r=qs.dataset.qs;if(L.status!==r){setStatus(L,r);L.knocks.at(-1).d=1}else L.knocks.push({t:Date.now(),r,d:1});saveLead(L);render();
    if(['Follow Up','Be Back','Inspection Scheduled','Inspected','Sold'].includes(r)){openLead(L.id);toast('Saved — set the follow-up')}else toast(addr(L)+' · '+r)}return}
  if(t.closest('[data-act="popclose"]')){S.selPin=null;render();return}
  if(t.closest('[data-act="unpin"]')&&S.selPin){const L=S.leads.get(S.selPin);if(L){delete L.pin;saveLead(L);S.mapMode='pin';const id=S.selPin;S.selPin=null;render();toast('Tap the roof where this house sits');S.rePin=id}return}
  const fs=t.closest('[data-fuseg]');if(fs){S.fuSeg=fs.dataset.fuseg;render();return}
  const mo=t.closest('[data-month]');if(mo){monthModal(+mo.dataset.month);return}
  const a=t.closest('[data-act]');const act=a&&a.dataset.act;
  if(act==='startsess'){S.settings.activeSession={start:Date.now()};saveSettings();render();toast('Session started — go get it');return}
  if(act==='endsess'){const as=S.settings.activeSession;if(!as)return;const st=windowStats(x=>x.t>=as.start);S.settings.sessions=(S.settings.sessions||[]).concat({start:as.start,end:Date.now(),...st}).slice(-60);S.settings.activeSession=null;saveSettings();render();toast(`Session done: ${st.k} doors, ${st.c} contacts, ${st.a} appts`);return}
  if(act==='pdclose'){t.closest('.payday').remove();return}
  const l=S.open?S.leads.get(S.open):null;
  if(act==='knock'){knockModal();return}
  if(act==='backupnow'){exportJSON();return}
  if(act==='settings'){settingsModal();return}
  if(act==='sample'){loadSample();return}
  if(act==='close'){closeLead();return}
  if(act==='report'){openReport();return}
  if(act==='repclose'){t.closest('.report-wrap').remove();return}
  if(act==='repsave'&&l){toast('Making PDF…');if(!(await ensureJsPDF())){toast('Couldn’t load the PDF maker — connect to the internet once and try again');return}try{const blob=await reportPDF(l);await save(`Inspection - ${addr(l).replace(/[^\w\- ]/g,'')}.pdf`,blob)}catch(err){toast('Couldn’t make the PDF: '+(err.message||err))}return}
  if(act==='annclose'){$('#layer .ann')?.remove();renderSheet();return}
  if(act==='annprev'&&l){ANN.i=(ANN.i-1+l.photos.length)%l.photos.length;renderAnn();return}
  if(act==='annnext'&&l){ANN.i=(ANN.i+1)%l.photos.length;renderAnn();return}
  if(act==='annundo'&&l){l.photos[ANN.i].marks.pop();saveLead(l,{quiet:true});renderAnn();return}
  if(act==='togrep'&&l){const p=l.photos[ANN.i];p.rep=p.rep===false;saveLead(l,{quiet:true});renderAnn();return}
  if(act==='delphoto'&&l){if(!(await confirmBox('Delete this photo for good?')))return;const p=l.photos.splice(ANN.i,1)[0];saveLead(l);
    if(p.asset&&S.assets)S.assets.delete(p.asset).catch(()=>{});else idbDel(p.id).catch(()=>{});
    if(!l.photos.length){$('#layer .ann')?.remove();renderSheet()}else{ANN.i=Math.min(ANN.i,l.photos.length-1);renderAnn()}return}
  if(!l&&!t.closest('.ann'))return;
  const mk=t.closest('[data-mk]');if(mk){ANN.mark=mk.dataset.mk;renderAnn();return}
  const ph=t.closest('[data-phase]');if(ph){l.photos[ANN.i].phase=ph.dataset.phase;saveLead(l,{quiet:true});renderAnn();return}
  const pi=t.closest('[data-ph]');if(pi){openAnn(+pi.dataset.ph);return}
  const st=t.closest('[data-status]');if(st){setStatus(l,st.dataset.status);saveLead(l);renderSheet();
    if(st.dataset.status==='Sold')toast('Sold — fill in the contract value below');return}
  const fu=t.closest('[data-fu]');if(fu){const k=fu.dataset.fu,d=new Date();
    if(k==='tom'){d.setDate(d.getDate()+1);d.setHours(10,0,0,0)}if(k==='3d'){d.setDate(d.getDate()+3);d.setHours(10,0,0,0)}if(k==='1w'){d.setDate(d.getDate()+7);d.setHours(10,0,0,0)}
    if(k==='spring'){d.setMonth(2,15);d.setHours(10,0,0,0);if(d<new Date())d.setFullYear(d.getFullYear()+1)}
    l.followAt=k==='clear'?'':localDT(d);if(k!=='clear'&&['Not Home','Not Interested'].includes(l.status)&&k)setStatus(l,'Follow Up');
    saveLead(l);renderSheet();toast(k==='clear'?'Follow-up cleared':'Follow-up: '+fmtWhen(l.followAt));return}
  const cs=t.closest('[data-cs]');if(cs){const was=l.sale.cstatus;l.sale.cstatus=cs.dataset.cs;if(cs.dataset.cs==='paid'&&!l.sale.paidAt)l.sale.paidAt=todayKey();saveLead(l);renderSheet();if(cs.dataset.cs==='paid'&&was!=='paid')celebrate(l);return}
  const jt=t.closest('[data-jobtype]');if(jt){l.sale.type=jt.dataset.jobtype;saveLead(l);renderSheet();return}
  const sv2=t.closest('[data-stormv]');if(sv2){l.storms[+sv2.dataset.stormv].verified=sv2.dataset.v==='1';saveLead(l);renderSheet();return}
  const ds=t.closest('[data-delstorm]');if(ds){l.storms.splice(+ds.dataset.delstorm,1);saveLead(l);renderSheet();return}
  const dl=t.closest('[data-delline]');if(dl){l.est.lines.splice(+dl.dataset.delline,1);saveLead(l);renderSheet();return}
  const dd=t.closest('[data-deldoc]');if(dd){if(!(await confirmBox('Remove this document?','Remove')))return;const d=l.docs.splice(+dd.dataset.deldoc,1)[0];saveLead(l);if(d.asset&&S.assets)S.assets.delete(d.asset).catch(()=>{});renderSheet();return}
  if(act==='addroute'){if(RT.ids.includes(l.id)){toast('Already on today’s route');return}addToRoute([l.id]);toast(`Added — stop ${RT.ids.length} on your route`);renderSheet();return}
  if(act==='findmap'){if(!l.geo){toast('Looking up the address…');const g=await geocode(fullAddr(l));if(!g){toast('Couldn’t find that address — pin it by tapping the roof');S.rePin=l.id;S.mapMode='pin';S.tab='knock';S.knockView='map';closeLead();location.hash='knock';return}l.geo=g;saveLead(l)}
    S.flyTo=l.geo;S.selPin=l.id;S.knockView='map';S.mapMode='browse';closeLead();if(location.hash!=='#map')location.hash='map';else render();return}
  if(act==='ref'){l.ref=!l.ref;saveLead(l);renderSheet();toast(l.ref?'Marked as reference customer':'Reference removed');return}
  if(act==='applycalc'){const r=roofCalc(l);if(!r.sq){toast('Enter the footprint first');return}l.roof.squares=r.sq.toFixed(1);l.roof.pitch=r.pitch+'/12';saveLead(l);renderSheet();toast(`Roof set to ${l.roof.squares} SQ, ${l.roof.pitch}`);return}
  if(act==='addstorm'){l.storms.push({date:'',hail:'',wind:'',src:'',verified:false});saveLead(l);renderSheet();return}
  if(act==='addnote'){const v=$('#newnote').value.trim();if(!v)return;l.log.push({t:Date.now(),text:v,by:S.me});saveLead(l);renderSheet();toast('Note saved');return}
  if(act==='useest'){l.sale.value=String(Math.round(estTotal(l)*100)/100);saveLead(l);renderSheet();return}
  if(act==='sigclear'){initSig($('#sigpad'));return}
  if(act==='sigsave'){const c=$('#sigpad');if(!c._ink){toast('Have the homeowner sign in the box first');return}
    const b=await new Promise(r=>c.toBlob(r,'image/png'));const id=await storeLocal(b);
    l.est.sig={id,asset:null};l.est.sigName=$('#signame').value.trim()||l.name;l.est.sigAt=Date.now();l.log.push({t:Date.now(),text:'Estimate signed by '+(l.est.sigName||'homeowner')});
    saveLead(l);renderSheet();uploadPending();toast('Signature saved');return}
  if(act==='clearsig'){if(!(await confirmBox('Clear the signature? The homeowner will need to sign again.','Clear')))return;l.est.sig=null;l.est.sigName='';l.est.sigAt='';saveLead(l);renderSheet();return}
  if(act==='share'){const txt=[`${l.name||'Homeowner'} — ${fullAddr(l)}`,`Status: ${l.status}`,l.phone&&`Phone: ${l.phone}`,l.ins.carrier&&`Carrier: ${l.ins.carrier}${l.ins.claim?' · Claim '+l.ins.claim:''}`,
    l.roof.squares&&`Roof: ${l.roof.squares} SQ ${l.roof.pitch||''} ${l.roof.material||''}`,l.storms.length&&`Storms: ${l.storms.map(s=>(s.date||'?')+(s.hail?' '+s.hail+'" hail':'')+(s.verified?' (verified)':' (reported)')).join('; ')}`,
    l.findings&&`Findings: ${l.findings}`,l.sale.value&&`Contract: ${money(num(l.sale.value)+num(l.sale.upgrades)+num(l.sale.supplements))} (${l.sale.type})`,`Photos: ${l.photos.length}`].filter(Boolean).join('\n');
    try{await navigator.clipboard.writeText(txt);toast('Summary copied — paste it to the office')}catch(err){const m=modal(`<h2>Summary</h2><textarea style="min-height:200px" id="sumtxt">${esc(txt)}</textarea><div><button class="btn" data-c="x">Close</button></div>`);m.addEventListener('click',ev=>{if(ev.target.closest('[data-c]'))m.remove()});$('#sumtxt',m).select()}return}
  if(act==='dellead'){if(!(await confirmBox(`Delete ${addr(l)} and all its photos? This can’t be undone.`)))return;
    for(const f of [...l.photos,...l.docs,...(l.est.sig?[l.est.sig]:[])]){if(f.asset&&S.assets)S.assets.delete(f.asset).catch(()=>{});else idbDel(f.id).catch(()=>{})}
    S.leads.delete(l.id);S.dirty.delete(l.id);S.deleted.add(l.id);persist();flush();closeLead();toast('Lead deleted');return}
});

document.addEventListener('submit',e=>{const f=e.target.closest('[data-addhouse]');if(!f)return;e.preventDefault();
  const n=f.querySelector('input').value.trim();knockModal({num:n,street:f.dataset.addhouse,city:f.dataset.city})});

let typeT=null;
document.addEventListener('input',e=>{const t=e.target;
  if(t.id==='leadq'){S.leadQ=t.value;clearTimeout(typeT);typeT=setTimeout(()=>{const p=t.selectionStart;render();const n=$('#leadq');n.focus();n.setSelectionRange(p,p)},200);return}
  const l=S.open&&S.leads.get(S.open);if(!l)return;
  if(t.dataset.f){setP(l,t.dataset.f,t.value);saveLead(l,{quiet:true});
    if(t.dataset.f.startsWith('sale.')){const o=$('#commout');if(o)o.textContent=money(commission(l))}
    if(t.dataset.f.startsWith('roof.calc')){const r=roofCalc(l);$('#calcsq').textContent=r.sq?r.sq.toFixed(1)+' SQ':'—';$('#calcarea').textContent=calcText(l)}return}
  if(t.dataset.storm){l.storms[+t.dataset.storm][t.dataset.k]=t.value;saveLead(l,{quiet:true});return}
  if(t.dataset.line){l.est.lines[+t.dataset.line][t.dataset.k]=t.value;saveLead(l,{quiet:true});const o=$('#esttot');if(o)o.textContent=money2(estTotal(l));return}
  if(t.dataset.pf){l.photos[ANN.i][t.dataset.pf]=t.value;saveLead(l,{quiet:true});return}
});
document.addEventListener('change',e=>{const t=e.target;const l=S.open&&S.leads.get(S.open);
  if(t.dataset.photo){addPhotos([...t.files]);t.value='';return}
  if(t.hasAttribute('data-doc')){addDoc(t.files[0]);t.value='';return}
  if(t.id==='newslope'){S.lastSlope=t.value;persist();return}
  if(t.id==='preset'&&l){const v=t.value;if(!v)return;const p=v==='custom'?{d:'',u:'',p:0}:PRESETS[+v];
    const q=p.u==='SQ'&&num(l.roof.squares)?String(Math.ceil(num(l.roof.squares)*1.1)):'';l.est.lines.push({d:p.d,u:p.u,q,p:String(p.p||'')});saveLead(l);renderSheet();return}
  if(t.dataset.pf==='slope'&&l){S.lastSlope=t.value;renderAnn();return}
  if(t.dataset.f==='followAt'&&l){saveLead(l);renderSheet();return}
  if(t.dataset.f==='sale.stage'&&l&&['Installed','Final check paid'].includes(t.value)&&l.sale.cstatus==='pending'){l.sale.cstatus='earned';saveLead(l);toast('Job installed — commission now owed to you')}
  if(t.dataset.f&&['num','street','name','sale.stage','roof.squares','roof.calc.pitch','roof.calc.cx'].includes(t.dataset.f)&&l){renderSheet()}
});
document.addEventListener('keydown',e=>{if(e.key!=='Escape')return;
  if($('#layer .modal')){$('#layer .modal:last-child')?.remove();return}
  if($('#layer .report-wrap')){$('#layer .report-wrap').remove();return}
  if($('#layer .ann')){$('#layer .ann').remove();renderSheet();return}
  if(S.open)closeLead()});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'){render();if(S.open&&!sheetBusy())renderSheet()}});

/* ---------- core: accounts, workspace, sync ---------- */
const CFG=window.RIDGELINE_CONFIG||{};
Object.assign(S,{me:null,email:'',api:null,wsList:[],ws:null,role:null,members:new Map(),pins:[],openBoard:[],terr:[],feed:[],reads:{},recent:[],blocked:[],threadCache:{},
  leadSeg:'pipeline',teamSeg:'board',adminSeg:'team',lbPer:'week',lbBoard:'hustle',lb:[],lbMonth:[],lbToday:[],terrDraft:null,colorBy:'status',chat:null});
const isCompany=()=>!!S.ws&&S.ws.kind==='company';
const isMgr=()=>['owner','manager'].includes(S.role);
const viewAll=()=>['owner','manager','office'].includes(S.role);
const isOffice=()=>S.role==='office';
const wsSet=()=>(S.ws&&S.ws.settings)||{};
const mname=id=>id===S.me?'You':((S.members.get(id)||{}).display_name||'Teammate');
const mfirst=id=>id===S.me?'You':(mname(id).split(' ')[0]);
const initials=id=>{const n=(S.members.get(id)||{}).display_name||'?';return n.split(/\s+/).map(x=>x[0]).join('').slice(0,2).toUpperCase()};
const REP_COLORS=['#2F6BFF','#E5372B','#12A150','#8B5CF6','#E58A00','#0EA5B7','#DB2777','#5B6B82','#B7791F','#16A34A'];
const repColor=id=>{const ids=[...S.members.keys()];const i=Math.max(0,ids.indexOf(id));return REP_COLORS[i%REP_COLORS.length]};
const isNet=e=>!navigator.onLine||/fetch|network|Load failed|timed? ?out|NetworkError/i.test(String((e&&e.message)||e));
const prefKey=()=>'rlt.prefs.'+(S.me||'x')+'.'+((S.ws&&S.ws.id)||'x');
function loadPrefs(){S.settings={...DEF_SETTINGS,...lsGet(prefKey(),{})};applyIdentity()}
function applyIdentity(){const m=S.members.get(S.me);if(m)S.settings.repName=m.display_name;
  if(S.ws){S.settings.company=S.ws.kind==='company'?S.ws.name:'';S.settings.terms=wsSet().terms||DEF_SETTINGS.terms;if(!S.settings.goalSet)S.settings.goal=num(wsSet().goal)||S.settings.goal}}
function saveSettings(){lsSet(prefKey(),S.settings);updateSync()}
const cacheKey=()=>'rlt.cache.'+S.me+'.'+S.ws.id;
function persist(){if(!S.ws)return;try{localStorage.setItem(cacheKey(),JSON.stringify({leads:[...S.leads.values()],dirty:[...S.dirty],deleted:[...S.deleted]}))}catch(e){}}
function loadCache(){S.leads=new Map();S.dirty=new Set();S.deleted=new Set();
  try{const o=JSON.parse(localStorage.getItem(cacheKey())||'null');if(o){o.leads.forEach(l=>S.leads.set(l.id,norm(l)));o.dirty.forEach(d=>S.dirty.add(d));(o.deleted||[]).forEach(d=>S.deleted.add(d))}}catch(e){}}

/* who did it, and where they were standing */
function stamp(){const g=MV.gps.pos;return{by:S.me,...(g?{gps:{lat:+g.lat.toFixed(6),lng:+g.lng.toFixed(6)}}:{})}}
function quickPos(){return new Promise(res=>{if(MV.gps.pos||!navigator.geolocation)return res(MV.gps.pos);let done=false;
  setTimeout(()=>{if(!done){done=true;res(null)}},2500);
  navigator.geolocation.getCurrentPosition(p=>{if(done)return;done=true;MV.gps.pos={lat:p.coords.latitude,lng:p.coords.longitude};res(MV.gps.pos)},()=>{if(!done){done=true;res(null)}},{enableHighAccuracy:true,maximumAge:60000,timeout:2400})})}

let flushT=null;
function touchActivity(l){if(l.owner_id!==S.me)return;
  if(l.origin==='company'&&l.claimed_at&&!l.contacted_at)l.contacted_at=new Date().toISOString();
  l.protected_until=new Date(Date.now()+(num(wsSet().protect_days)||30)*864e5).toISOString()}
function saveLead(l,{quiet}={}){l.updated=Date.now();if(!l.created_by)l.created_by=S.me;if(l.owner_id===undefined)l.owner_id=S.me;
  if(!l._saved&&l.pinned_lat==null&&MV.gps.pos){l.pinned_lat=+MV.gps.pos.lat.toFixed(6);l.pinned_lng=+MV.gps.pos.lng.toFixed(6)}
  touchActivity(l);S.leads.set(l.id,l);S.dirty.add(l.id);persist();clearTimeout(flushT);flushT=setTimeout(flush,quiet?900:150);updateSync()}
async function flush(){if(!S.api||!S.ws||S.flushing)return;S.flushing=true;updateSync();
  try{
    for(const id of [...S.deleted]){try{await S.api.deleteLead(S.ws.id,id);S.deleted.delete(id)}catch(e){if(isNet(e))break;S.deleted.delete(id)}}
    for(const id of [...S.dirty]){const l=S.leads.get(id);if(!l){S.dirty.delete(id);continue}const st=l.updated;
      try{await S.api.saveLead(S.ws.id,l);S.online=true;if((S.leads.get(id)||{}).updated===st)S.dirty.delete(id)}
      catch(e){if(isNet(e)){S.online=false;break}toast('Couldn’t save '+addr(l)+' — '+e.message);S.dirty.delete(id)}}
  }finally{S.flushing=false;persist();updateSync();if(S.dirty.size)setTimeout(flush,15000)}}
function updateSync(){const el=$('#sync');if(!el)return;const n=S.dirty.size+S.deleted.size;let cls='',txt='';
  if(!S.api){cls='off';txt='Starting…'}
  else if(S.api.mode==='demo'){cls='warn';txt='Demo'+(S.me?' · '+mfirst(S.me).replace('You',(S.members.get(S.me)||{}).display_name?.split(' ')[0]||'You'):'')}
  else if(!S.online){cls='warn';txt=n?`Offline · ${n} waiting`:'Offline'}
  else if(n||S.flushing||S.uploading){cls='warn';txt='Saving…'}
  else txt='Synced';
  el.innerHTML=`<span class="dot ${cls}"></span><span>${esc(txt)}</span>`}

/* photos: kept on the phone until they reach cloud storage */
const fileSrc=f=>f?(f.asset?(S.urls.get(f.asset)||''):(S.urls.get(f.id)||'')):'';
async function ensureUrls(paths){const need=[...new Set(paths.filter(p=>p&&!S.urls.has(p)))];if(!need.length)return false;
  try{const m=await S.api.signedUrls(need);let any=false;for(const [p,u] of Object.entries(m)){S.urls.set(p,u);any=true}return any}catch(e){return false}}
const leadFilePaths=l=>[...l.photos,...l.docs,...(l.est.sig?[l.est.sig]:[])].map(f=>f.asset).filter(Boolean);
async function uploadPending(){if(!S.api||!S.ws||S.uploading||!navigator.onLine)return;S.uploading=true;updateSync();
  try{for(const l of S.leads.values()){if(l.owner_id&&l.owner_id!==S.me&&!isMgr())continue;
    const items=[...l.photos,...l.docs,...(l.est.sig?[l.est.sig]:[])].filter(f=>!f.asset);let changed=false;
    for(const f of items){let b;try{b=await idbGet(f.id)}catch(e){}if(!b)continue;
      try{const ext=(b.type||'image/jpeg').includes('png')?'png':(b.type||'').includes('pdf')?'pdf':'jpg';
        const p=await S.api.uploadFile(S.ws.id,l.id,b,ext);f.asset=p;S.urls.set(p,S.urls.get(f.id)||'');changed=true;await idbDel(f.id).catch(()=>{})}
      catch(e){if(isNet(e)){setTimeout(uploadPending,20000);return}toast('A photo couldn’t upload: '+e.message)}}
    if(changed){saveLead(l,{quiet:true});if(S.open===l.id&&!sheetBusy())renderSheet()}}}
  finally{S.uploading=false;updateSync()}}

/* loading */
async function loadWorkspaceData(){if(!S.ws)return;const ws=S.ws.id;
  try{const [mem,leads]=await Promise.all([S.api.members(ws),S.api.listLeads(ws)]);
    S.members=new Map(mem.map(m=>[m.user_id,m]));applyIdentity();
    const fresh=new Map(leads.map(l=>[l.id,norm(l)]));
    for(const id of S.dirty){const loc=S.leads.get(id);if(loc)fresh.set(id,loc)}
    for(const id of S.deleted)fresh.delete(id);
    S.leads=fresh;persist();S.online=true;
    try{S.zones=await S.api.skipZones(ws)||[]}catch(e){S.zones=[]}
    if(isCompany()){const [pins,board,terr]=await Promise.all([S.api.teamPins(ws),S.api.openLeads(ws),S.api.territories(ws)]);S.pins=pins||[];S.openBoard=board||[];S.terr=terr||[];
      S.api.releaseStale(ws).then(n=>{if(n){toast(`${n} unclaimed lead${n>1?'s':''} went back on the board`);refreshBoard()}});loadTeamNumbers()}
  }catch(e){if(isNet(e))S.online=false;else toast(e.message)}
  updateSync();renderSoft()}
async function refreshBoard(){if(!isCompany())return;try{const [b,p]=await Promise.all([S.api.openLeads(S.ws.id),S.api.teamPins(S.ws.id)]);S.openBoard=b||[];S.pins=p||[]}catch(e){}renderSoft()}
function periodRange(per){const d=new Date(),s=new Date(d);s.setHours(0,0,0,0);
  if(per==='week'){const w=(s.getDay()+6)%7;s.setDate(s.getDate()-w)}if(per==='month')s.setDate(1);return[s,new Date(d.getTime()+60e3)]}
async function loadTeamNumbers(){if(!isCompany())return;try{
  const [a,b]=periodRange(S.lbPer),[m0,m1]=periodRange('month'),[t0,t1]=periodRange('today');
  const [lb,lbm,lbt]=await Promise.all([S.api.leaderboard(S.ws.id,a,b),S.api.leaderboard(S.ws.id,m0,m1),S.api.leaderboard(S.ws.id,t0,t1)]);
  S.lb=lb;S.lbMonth=lbm;S.lbToday=lbt}catch(e){}renderSoft()}
async function loadFeed(){if(!isCompany())return;try{S.feed=await S.api.feed(S.ws.id)}catch(e){}if(['home','team'].includes(S.tab))renderSoft()}
async function loadMessages(){if(!isCompany())return;try{const [r,reads,bl]=await Promise.all([S.api.recentMessages(S.ws.id),S.api.myReads(S.ws.id),S.api.blocks()]);
  S.recent=r||[];S.reads=Object.fromEntries((reads||[]).map(x=>[x.thread,x.last_read_at]));S.blocked=bl||[]}catch(e){}updateBadges()}
function unreadCount(thread){return S.recent.filter(m=>(!thread||m.thread===thread)&&m.sender_id!==S.me&&!S.blocked.includes(m.sender_id)&&m.channel!=='lead'&&(!S.reads[m.thread]||m.created_at>S.reads[m.thread])).length}
function updateBadges(){const b=$('#teambadge');if(b){const n=unreadCount();b.hidden=!n;b.textContent=n>9?'9+':n}
  const f=$('#fubadge');if(f){const od=followLists().overdue.length;f.hidden=!od;f.textContent=od}}
let unsub=null;
function subscribeLive(){if(unsub)unsub();if(!isCompany())return;
  unsub=S.api.subscribe(S.ws.id,{onMessage:m=>{if(!S.recent.find(x=>x.id===m.id))S.recent.unshift(m);
      if(S.chat&&S.chat.thread===m.thread){(S.threadCache[m.thread]=S.threadCache[m.thread]||[]).push(m);renderChat();S.api.markRead(S.ws.id,m.thread);S.reads[m.thread]=new Date().toISOString()}
      else if(m.sender_id!==S.me&&!S.blocked.includes(m.sender_id)&&m.channel!=='lead')toast(`${mfirst(m.sender_id)}: ${m.body.slice(0,60)}`);
      if(m.channel==='lead'&&S.open&&m.thread==='lead:'+S.open){(S.threadCache[m.thread]=S.threadCache[m.thread]||[]);if(!S.threadCache[m.thread].find(x=>x.id===m.id))S.threadCache[m.thread].push(m);if(!sheetBusy())renderSheet()}
      updateBadges();if(S.tab==='team'&&S.teamSeg==='chat')renderSoft()},
    onFeed:()=>loadFeed()})}

/* ---------- boot ---------- */
async function boot(){
  S.online=navigator.onLine;S.dl={save:localSave};
  if(CFG.supabaseUrl&&CFG.supabaseAnonKey){try{({supabaseApi}=await import('./api/supabase.js'));S.api=supabaseApi(CFG.supabaseUrl,CFG.supabaseAnonKey)}catch(e){$('#view').innerHTML='<div class="card empty" style="margin-top:40px"><strong>Can’t reach Ridgeline</strong>Check your internet connection and open the app again.</div>';return}}else S.api=demoApi();
  window.addEventListener('online',()=>{S.online=true;updateSync();flush();uploadPending();loadWorkspaceData()});
  window.addEventListener('offline',()=>{S.online=false;updateSync()});
  try{navigator.storage&&navigator.storage.persist&&navigator.storage.persist()}catch(e){}
  await hydrateUrls();
  let sess=null;try{sess=await S.api.session()}catch(e){}
  if(!sess){showAuth();return}
  S.me=sess.user.id;S.email=sess.user.email;await enterApp();
  setInterval(()=>{if(document.visibilityState==='visible'&&S.ws&&navigator.onLine){loadWorkspaceData();loadMessages()}},90000);
}
async function enterApp(wsId){
  closeAllLayers();
  try{S.wsList=await S.api.workspaces()}catch(e){if(isNet(e)){S.wsList=lsGet('rlt.wslist.'+S.me,[])}else{toast(e.message);S.wsList=[]}}
  lsSet('rlt.wslist.'+S.me,S.wsList);
  if(!S.wsList.length){showOnboard();return}
  const last=wsId||lsGet('rlt.lastws.'+S.me,null);
  S.ws=S.wsList.find(w=>w.id===last)||S.wsList[0];S.role=S.ws.role;lsSet('rlt.lastws.'+S.me,S.ws.id);
  S.members=new Map();loadPrefs();loadCache();Object.assign(S,{pins:[],openBoard:[],terr:[],feed:[],recent:[],threadCache:{},lb:[],lbMonth:[],lbToday:[],open:null,selPin:null});
  RT.ids=[];RT.idx=0;RT.geom=null;Object.assign(RT,lsGet('rlt.route.'+S.me+'.'+S.ws.id,{}));
  if(MV.map){MV.map.remove();MV.map=null;MV.host=null}
  showShell();route();
  await loadWorkspaceData();flush();uploadPending();
  if(isCompany()){loadFeed();loadMessages();subscribeLive()}
}
function closeAllLayers(){$('#layer').innerHTML='';S.open=null;S.chat=null}

/* ---------- shell & routing ---------- */
const NAV_ICONS={
  home:'<path d="M3 11 12 3l9 8"/><path d="M5 10v10h14V10"/>',
  map:'<path d="M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12z"/><circle cx="12" cy="9" r="2.5"/>',
  leads:'<path d="M4 5h16M4 12h11M4 19h6"/>',
  team:'<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><circle cx="17" cy="9" r="2.5"/><path d="M15.5 14.2c3 .2 5.5 2.6 5.5 5.8"/>',
  money:'<path d="M12 2v20M17 6.5C17 4.6 14.8 4 12 4S7 5 7 7.5 9.5 10.5 12 11s5 1.4 5 4-2.2 3.5-5 3.5S7 17.6 7 15.5"/>',
  admin:'<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="9" cy="6" r="2" fill="currentColor"/><circle cx="15" cy="12" r="2" fill="currentColor"/><circle cx="7" cy="18" r="2" fill="currentColor"/>'};
const NAV_LABEL={home:'Home',map:'Map',leads:'Leads',team:'Team',money:'Money',admin:'Admin'};
function tabsFor(){return [...tabsForNav(),'tools','storms']}
function tabsForNav(){if(!isCompany())return['home','map','leads','money'];if(isMgr())return['home','map','leads','team','admin'];if(isOffice())return['home','map','leads','team'];return['home','map','leads','team','money']}
function showShell(){document.body.classList.remove('auth');
  $('#nav').innerHTML=`<div class="nav-in" style="grid-template-columns:repeat(${tabsForNav().length},1fr)">${tabsForNav().map(t=>`<button data-tab="${t}"><span class="nb-wrap"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">${NAV_ICONS[t]}</svg>${t==='team'?'<span class="nb" id="teambadge" hidden></span>':t==='leads'?'<span class="nb" id="fubadge" hidden></span>':''}</span>${NAV_LABEL[t]}</button>`).join('')}</div>`;
  $('#wsname').textContent=S.ws.kind==='company'?S.ws.name:'Ridgeline';
  $('.fab').hidden=isOffice();}
const TAB_ALIAS={knock:['map'],pipeline:['leads','pipeline'],followups:['leads','follow'],board:['leads','board']};
function route(){let h=location.hash.slice(1);const al=TAB_ALIAS[h];if(al){h=al[0];if(al[1])S.leadSeg=al[1];history.replaceState(null,'','#'+h)}
  const tabs=tabsFor();S.tab=tabs.includes(h)?h:'home';render()}
window.addEventListener('hashchange',()=>{if(S.ws)route()});
function render(){if(!S.ws)return;$$('.nav [data-tab]').forEach(b=>b.setAttribute('aria-current',b.dataset.tab===S.tab?'page':'false'));
  document.body.dataset.view=S.tab;const v=$('#view');v.innerHTML=({home:vHomeAll,map:vKnock,leads:vLeads,team:vTeam,money:vMoney,admin:vAdmin,tools:vTools,storms:vStorms}[S.tab]||vHomeAll)();
  updateSync();applyTheme();if($('#mapslot'))bindMap();updateBadges();$('.fab').hidden=isOffice()||['team','admin'].includes(S.tab)}
function sheetBusy(){const a=document.activeElement;return a&&a.closest&&a.closest('.sheet,.modal,.ann,.chat')&&/INPUT|TEXTAREA|SELECT/.test(a.tagName)}
function renderSoft(){if(!S.ws)return;const busyMain=document.activeElement&&document.activeElement.closest&&document.activeElement.closest('#view')&&/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName);
  if(!$('.modal')&&!$('.ann')&&!busyMain)render();if(S.open&&!sheetBusy()&&!$('.ann'))renderSheet()}
const leadsArr=()=>[...S.leads.values()];
const myLeads=()=>leadsArr().filter(l=>l.owner_id===S.me);

/* ---------- sign in & setup ---------- */
function showAuth(step='email'){document.body.classList.add('auth');$('#nav').innerHTML='';$('.fab').hidden=true;$('#wsname').textContent='Ridgeline';
  $('#view').innerHTML=`<div class="auth-card card">
    <div class="auth-logo"><svg width="34" height="34" viewBox="0 0 26 22" aria-hidden="true"><path d="M1 13 13 2l12 11" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 12v9h16v-9" fill="none" stroke="#fff" stroke-width="2.4" stroke-linejoin="round"/></svg></div>
    <h1>Ridgeline</h1><p class="muted" style="margin:0">Roofing sales, from the first knock to the commission check.</p>
    ${step==='email'?`<label class="field"><span>Email</span><input type="email" id="au-email" autocomplete="email" inputmode="email" placeholder="you@company.com" value="${esc(S.email||'')}"></label>
      <button class="btn pri" data-auth="send">Email me a sign-in code</button>`
    :`<p style="margin:0">We sent a 6-digit code to <b>${esc(S.email)}</b>.</p><label class="field"><span>Code</span><input type="text" id="au-code" inputmode="numeric" autocomplete="one-time-code" maxlength="8" placeholder="123456"></label>
      <button class="btn pri" data-auth="verify">Sign in</button><button class="btn" data-auth="back">Use a different email</button>`}</div>`;
  setTimeout(()=>$('#au-email,#au-code')?.focus(),50)}
function pendingJoin(){try{const q=new URLSearchParams(location.search).get('join');if(q){localStorage.setItem('rlt.pendingJoin',q.toUpperCase());history.replaceState(null,'',location.pathname+location.hash)}return localStorage.getItem('rlt.pendingJoin')||''}catch(e){return''}}
function showOnboard(){document.body.classList.add('auth');$('#nav').innerHTML='';$('.fab').hidden=true;const pj=pendingJoin();const meName=S.ws?((S.members.get(S.me)||{}).display_name||''):'';
  $('#view').innerHTML=`<div class="auth-card card">${S.ws?`<button class="btn sm" data-auth="cancel-ob" style="align-self:flex-start">‹ Back to ${esc(S.ws.kind==='company'?S.ws.name:'my account')}</button>`:''}<h1 style="font-size:26px">${S.ws?'Add an account':'Welcome'}</h1>
    <label class="field"><span>Your name</span><input type="text" id="ob-name" autocomplete="name" placeholder="First and last name" value="${esc(meName)}"></label>
    <div class="ob-opt${pj?' hl':''}"><b>Join my company</b><span class="muted">${pj?'Your invite code is filled in.':'Your manager gave you an invite code.'}</span><div class="row"><input type="text" id="ob-code" placeholder="Invite code" autocapitalize="characters" style="text-transform:uppercase" value="${esc(pj)}"><button class="btn pri" data-ob="join">Join</button></div></div>
    <div class="ob-opt"><b>Start a company</b><span class="muted">You run a sales team and will invite reps.</span><div class="row"><input type="text" id="ob-co" placeholder="Company name"><button class="btn" data-ob="company">Create</button></div></div>
    <div class="ob-opt"><b>Just me</b><span class="muted">An individual rep account. Your leads are yours.</span><button class="btn" data-ob="individual">Start solo</button></div>
    ${S.api.mode==='live'?'<button class="btn sm" data-auth="signout" style="align-self:center">Sign out</button>':''}</div>`}
async function authClick(t){const a=t.closest('[data-auth]'),o=t.closest('[data-ob]');if(!a&&!o)return false;
  try{
    if(a&&a.dataset.auth==='send'){const e=$('#au-email').value.trim();if(!/.+@.+\..+/.test(e)){toast('Enter your email');return true}S.email=e;a.disabled=true;await S.api.sendCode(e);showAuth('code')}
    if(a&&a.dataset.auth==='verify'){const c=$('#au-code').value.trim();if(c.length<6){toast('Enter the code from the email');return true}a.disabled=true;const s=await S.api.verifyCode(S.email,c);S.me=s.user.id;await enterApp()}
    if(a&&a.dataset.auth==='back')showAuth('email');
    if(a&&a.dataset.auth==='cancel-ob'){document.body.classList.remove('auth');await enterApp(S.ws.id)}
    if(a&&a.dataset.auth==='signout'){await S.api.signOut();location.reload()}
    if(o){const name=$('#ob-name').value.trim();if(!name){toast('Add your name first');$('#ob-name').focus();return true}let id;
      if(o.dataset.ob==='join'){const code=$('#ob-code').value.trim();if(!code){toast('Enter the invite code');return true}id=await S.api.joinWorkspace(code,name);try{localStorage.removeItem('rlt.pendingJoin')}catch(e){}}
      if(o.dataset.ob==='company'){const co=$('#ob-co').value.trim();if(!co){toast('Name your company');return true}id=await S.api.createWorkspace(co,'company',name)}
      if(o.dataset.ob==='individual')id=await S.api.createWorkspace(name,'individual',name);
      await enterApp(id)}
  }catch(e){const m=String(e.message||'');toast(/fetch|network|load failed/i.test(m)?'Can’t reach the server — check your signal (or the Supabase URL in config.js)':/token|otp|expired|invalid/i.test(m)&&a&&a.dataset.auth==='verify'?'That code didn’t work — check it, or go back and send a new one':/rate limit|too many|security purposes/i.test(m)?'Too many codes sent — wait a minute and try again':/invalid api key|apikey/i.test(m)?'The app’s Supabase key is wrong — check config.js':m||'Something went wrong');if(a)a.disabled=false}
  return true}

/* ---------- HOME ---------- */
function seg(name,cur,items){return `<div class="seg" role="tablist" style="grid-template-columns:repeat(${items.length},1fr)">${items.map(([k,t,n])=>`<button role="tab" data-${name}="${k}" aria-selected="${cur===k}">${t}${n!=null&&n!==''?` <span class="num" style="opacity:.6">${n}</span>`:''}</button>`).join('')}</div>`}
function teamGoalHTML(){const g=wsSet().team_goal;if(!g||!g.target)return'';const metric=g.metric||'doors';
  const val=S.lbMonth.reduce((a,r)=>a+num(r[metric]),0);const pct=Math.min(100,Math.round(val/g.target*100));
  return `<section class="card pad goalcard"><div class="row"><span class="grow"><span class="label">Team goal</span><b style="display:block;font-size:16px">${esc(g.label||'Team goal')}</b></span><b class="num" style="font-size:20px">${metric==='volume'?money(val):val} <span class="muted" style="font-size:13px;font-weight:600">/ ${metric==='volume'?money(g.target):g.target}</span></b></div>
    <div class="goalbar2"><span style="width:${pct}%"></span></div></section>`}
function myRankLine(){if(!isCompany()||wsSet().leaderboards===false||!S.lb.length)return'';const rows=S.lb.filter(r=>(S.members.get(r.user_id)||{}).role!=='office').sort((a,b)=>b.doors-a.doors);
  const i=rows.findIndex(r=>r.user_id===S.me);if(i<0)return'';const ahead=rows[i-1];
  return `<button class="card live-strip" data-tab="team"><span class="rank-badge">#${i+1}</span><b>in doors this ${S.lbPer==='today'?'day':S.lbPer}</b><span class="muted">${ahead?`${ahead.doors-rows[i].doors} behind ${esc(mfirst(ahead.user_id))}`:'Leading the team'}</span><span class="grow"></span><span class="muted">›</span></button>`}
function vHomeAll(){return viewAll()?vDashboard():vHome().replace('<section class="card money-hero">',`${isCompany()&&S.openBoard.length?`<button class="card live-strip board-strip" data-gotoboard="1"><span class="rt-n" style="background:var(--s-sched)">${S.openBoard.length}</span><b>Open lead${S.openBoard.length>1?'s':''} on the board</b><span class="grow"></span><span class="muted">Claim ›</span></button>`:''}${myRankLine()}${isCompany()?teamGoalHTML():''}<section class="card money-hero">`)}
function vDashboard(){
  const sum=(rows,k)=>rows.reduce((a,r)=>a+num(r[k]),0);const T=S.lbToday,M=S.lbMonth;
  const allLeads=leadsArr();const now=Date.now();
  const overdue=allLeads.filter(l=>l.followAt&&!LOST.includes(l.status)&&new Date(l.followAt).getTime()<now&&l.owner_id);
  const waiting=allLeads.filter(l=>l.origin==='company'&&l.owner_id&&l.claimed_at&&!l.contacted_at);
  const reps=M.filter(r=>['rep','manager','owner'].includes((S.members.get(r.user_id)||{}).role)).sort((a,b)=>b.volume-a.volume||b.sales-a.sales||b.doors-a.doors);
  const insp=sum(M,'inspections'),sales=sum(M,'sales');
  const oldest=S.openBoard.reduce((a,o)=>Math.min(a,Date.parse(o.posted_at)||now),now);
  const d=new Date();
  return `<div class="stack">
  <div class="row" style="align-items:flex-end"><div class="grow"><div class="label">${d.toLocaleDateString([], {weekday:'long',month:'long',day:'numeric'})}</div>
    <h1 style="font-size:30px;margin-top:2px">${esc(S.ws.name)}</h1></div>
    ${viewAll()?`<button class="btn sm pri" data-act="postlead">+ Post lead</button>`:''}</div>
  <section class="card money-hero"><div class="label">Team this month</div><div class="big">${money(sum(M,'volume'))}</div>
    <div class="muted" style="font-size:13px">contract volume · ${sales} sale${sales===1?'':'s'} · ${insp?Math.min(100,Math.round(sales/insp*100)):0}% close rate</div>
    <div class="hero-split"><div><span class="muted">Doors</span><b>${sum(M,'doors')}</b></div><div><span class="muted">Appts</span><b>${sum(M,'appts')}</b></div><div><span class="muted">Inspections</span><b>${insp}</b></div></div></section>
  <div><div class="sec-h"><h2>Today</h2></div><div class="kpis">
    <div class="card kpi"><b>${sum(T,'doors')}</b><span class="label">Doors</span></div>
    <div class="card kpi"><b>${sum(T,'contacts')}</b><span class="label">Contacts</span></div>
    <div class="card kpi"><b>${sum(T,'appts')}</b><span class="label">Appts set</span></div></div></div>
  ${teamGoalHTML()}
  <div class="kpis">
    <button class="card kpi tapk" data-gotoboard="1"><b style="color:var(--s-sched)">${S.openBoard.length}</b><span class="label">On the board${S.openBoard.length?' · oldest '+agoShort(oldest):''}</span></button>
    <button class="card kpi tapk ${waiting.length?'warnk':''}" data-gotoboard="1"><b>${waiting.length}</b><span class="label">Claimed, not contacted</span></button>
    <button class="card kpi tapk ${overdue.length?'alert':''}" data-leadseg="follow"><b>${overdue.length}</b><span class="label">Overdue follow-ups</span></button></div>
  <section><div class="sec-h"><h2>Reps this month</h2><button class="linkbtn" data-tab="admin" data-adminseg="reports">Full report ›</button></div>
    ${reps.length?`<div class="card scroll-x"><table class="tbl"><thead><tr><th>Rep</th><th class="r">Doors</th><th class="r">Appts</th><th class="r">Sales</th><th class="r">Volume</th></tr></thead><tbody>
      ${reps.map(r=>`<tr><td><span class="av" style="--c:${repColor(r.user_id)}">${esc(initials(r.user_id))}</span>${esc(r.display_name||mname(r.user_id))}</td><td class="r">${r.doors}</td><td class="r">${r.appts}</td><td class="r">${r.sales}</td><td class="r"><b>${money(r.volume)}</b></td></tr>`).join('')}</tbody></table></div>`
      :'<div class="card empty"><strong>No activity yet</strong>Numbers fill in as your reps log doors.</div>'}</section>
  ${S.feed.length?`<section><div class="sec-h"><h2>Team wins</h2><button class="linkbtn" data-tab="team" data-teamseg="feed">All ›</button></div><div class="card list">${S.feed.slice(0,3).map(feedRow).join('')}</div></section>`:''}
  </div>`}
function agoShort(t){const m=Math.round((Date.now()-t)/60000);return m<60?m+'m':m<1440?Math.round(m/60)+'h':Math.round(m/1440)+'d'}

/* ---------- LEADS (pipeline / follow-ups / open board) ---------- */
function vLeads(){
  const F=followLists();const segs=[['pipeline',viewAll()?'All leads':'My leads'],['follow','Follow-ups',F.overdue.length?'⚠'+F.overdue.length:'']];
  if(isCompany())segs.push(['board','Open board',S.openBoard.length||'']);
  const segH=seg('leadseg',S.leadSeg,segs);
  let inner=S.leadSeg==='follow'?vFollow():S.leadSeg==='board'&&isCompany()?vBoard():vPipeline();
  inner=inner.replace(/<div class="sec-h"><h2 style="font-size:28px;letter-spacing:-.03em">(Pipeline|Follow-ups)<\/h2>/,'<div class="sec-h"><h2 style="font-size:28px;letter-spacing:-.03em">Leads</h2>');
  return inner.replace('</div>',`</div>${segH}`)}
function distTo(lat,lng){const g=MV.gps.pos;if(!g||lat==null)return'';const d=hav(g,{lat,lng});return d<.1?'nearby':d.toFixed(1)+' mi'}
function vBoard(){
  const hrs=num(wsSet().claim_deadline_hours)||2,cap=num(wsSet().claim_cap)||3;
  const mine=leadsArr().filter(l=>l.origin==='company'&&l.owner_id===S.me&&l.claimed_at&&!l.contacted_at);
  const waiting=viewAll()?leadsArr().filter(l=>l.origin==='company'&&l.owner_id&&l.claimed_at&&!l.contacted_at):[];
  const full=viewAll()?new Map(leadsArr().filter(l=>l.pool).map(l=>[l.id,l])):new Map();
  let h=`<div class="stack"><div class="sec-h"><h2 style="font-size:28px;letter-spacing:-.03em">Leads</h2>${viewAll()?'<button class="btn sm pri" data-act="postlead">+ Post lead</button>':''}</div>`;
  if(!viewAll())h+=`<p class="muted" style="margin:0 2px;font-size:13.5px">Call-ins from the office. Claim one and you have ${hrs} hour${hrs===1?'':'s'} to make contact or it goes back on the board. You can hold ${cap} unworked at a time.</p>`;
  if(mine.length)h+=`<section><div class="label" style="margin:0 2px 8px">Claimed by you — contact them</div><div class="card list">${mine.map(l=>{const left=hrs*3600e3-(Date.now()-Date.parse(l.claimed_at));return `<button class="li" data-open="${l.id}"><span class="stripe" style="--c:var(--s-sched)"></span><span class="grow"><span class="t1 trunc" style="display:block">${esc(l.name||addr(l))}</span><span class="t2 trunc" style="display:block">${esc(addr(l))} · ${esc(l.phone||'')}</span></span><span class="when ${left<1800e3?'late':''}">${left>0?Math.ceil(left/60e3)+' min left':'Overdue'}</span></button>`}).join('')}</div></section>`;
  h+=S.openBoard.length?`<div class="board">${S.openBoard.map(o=>{const f=full.get(o.id);return `<article class="card board-card">
      <div class="row"><span class="job-tag">${esc(o.job||'Inspection')}</span>${o.insurance?'<span class="job-tag ins">Insurance</span>':''}<span class="grow"></span><span class="muted" style="font-size:12.5px">${agoShort(Date.parse(o.posted_at))} ago</span></div>
      <div><b style="font-size:17px">${f?esc(f.name||addr(f)):esc(o.street)}</b><div class="muted" style="font-size:13.5px">${f?esc(fullAddr(f))+(f.phone?' · '+esc(f.phone):''):esc(o.city)+(distTo(o.lat,o.lng)?' · '+distTo(o.lat,o.lng):'')}</div></div>
      ${o.window_text?`<div style="font-size:14px"><span class="muted">Wants:</span> ${esc(o.window_text)}</div>`:''}${o.notes?`<div style="font-size:14px">${esc(o.notes)}</div>`:''}
      <div class="muted" style="font-size:12.5px">${esc(o.source||'Office')} · posted by ${esc(mfirst(o.posted_by))}</div>
      <div class="btns">${viewAll()?`<select data-assignpool="${o.id}" aria-label="Assign to rep" style="flex:1;min-height:42px"><option value="">Assign to…</option>${[...S.members.values()].filter(m=>m.active&&['rep','manager','owner'].includes(m.role)).map(m=>`<option value="${m.user_id}">${esc(m.display_name)}</option>`).join('')}</select><button class="btn dng" data-delpool="${o.id}">Delete</button>`:''}
        ${S.role!=='office'?`<button class="btn pri grow" data-claim="${o.id}">Claim</button>`:''}</div></article>`}).join('')}</div>`
    :`<div class="card empty"><strong>The board is clear</strong>${viewAll()?'Post a call-in and every rep gets it.':'When the office posts a call-in, it shows up here.'}</div>`;
  if(waiting.length)h+=`<section><div class="label" style="margin:0 2px 8px">Claimed, not contacted yet</div><div class="card list">${waiting.map(l=>{const left=hrs*3600e3-(Date.now()-Date.parse(l.claimed_at));return `<button class="li" data-open="${l.id}"><span class="av" style="--c:${repColor(l.owner_id)}">${esc(initials(l.owner_id))}</span><span class="grow"><span class="t1 trunc" style="display:block">${esc(l.name||addr(l))}</span><span class="t2" style="display:block">${esc(mname(l.owner_id))} · claimed ${agoShort(Date.parse(l.claimed_at))} ago</span></span><span class="when ${left<0?'late':''}">${left>0?Math.ceil(left/60e3)+'m left':'Late'}</span></button>`}).join('')}</div></section>`;
  return h+'</div>'}
function postLeadModal(){
  const reps=[...S.members.values()].filter(m=>m.active&&['rep','manager','owner'].includes(m.role));
  const m=modal(`<div class="row"><h2 class="grow">Post a lead</h2><button class="iconbtn" data-c="x" aria-label="Close">✕</button></div>
    <div class="grid2"><label class="field"><span>Homeowner</span><input type="text" id="pl-name" autocomplete="off"></label><label class="field"><span>Phone</span><input type="tel" id="pl-phone" autocomplete="off"></label></div>
    <div class="grid2" style="grid-template-columns:100px 1fr"><label class="field"><span>House #</span><input type="text" id="pl-num" inputmode="numeric"></label><label class="field"><span>Street</span><input type="text" id="pl-street"></label></div>
    <label class="field"><span>City, state</span><input type="text" id="pl-city" value="${esc(S.settings.city||'')}"></label>
    <div class="grid2"><label class="field"><span>What they want</span><select id="pl-job">${['Inspection','Storm damage','Leak','Estimate','Repair','Gutters','Other'].map(x=>`<option>${x}</option>`).join('')}</select></label>
      <label class="field"><span>Source</span><select id="pl-src">${['Phone call','Website','Referral','Yard sign','Social media','Other'].map(x=>`<option>${x}</option>`).join('')}</select></label></div>
    <label class="field"><span>When they want it</span><input type="text" id="pl-win" placeholder="Tomorrow morning, after 4 PM…"></label>
    <label class="row" style="gap:10px"><input type="checkbox" id="pl-ins" style="width:22px;height:22px"><span>Insurance claim likely</span></label>
    <label class="field"><span>Notes reps see before claiming</span><textarea id="pl-pub" placeholder="Shingles in the yard after Tuesday’s storm"></textarea></label>
    <label class="field"><span>Send to</span><select id="pl-to"><option value="">Open board — first rep to claim gets it</option>${reps.map(r=>`<option value="${r.user_id}">Assign to ${esc(r.display_name)}</option>`).join('')}</select></label>
    <button class="btn pri" data-c="post">Post lead</button>`);
  m.addEventListener('click',async e=>{const c=e.target.closest('[data-c]');if(!c)return;if(c.dataset.c==='x'){m.remove();return}
    const v=id=>$('#'+id,m).value.trim();if(!v('pl-street')){toast('Add the street address');return}
    c.disabled=true;c.textContent='Posting…';
    const l=newLead({num:v('pl-num'),street:v('pl-street'),city:v('pl-city'),name:v('pl-name'),phone:v('pl-phone'),source:v('pl-src'),status:'Inspection Scheduled',
      sale:{...newLead().sale,type:$('#pl-ins',m).checked?'Insurance':'Retail'},post:{job:v('pl-job'),insurance:$('#pl-ins',m).checked,window:v('pl-win'),source:v('pl-src'),public_notes:v('pl-pub')}});
    l.geo=await geocode(fullAddr(l));l.knocks=[{t:Date.now(),r:'Posted',by:S.me}];
    try{await S.api.postOpenLead(S.ws.id,l);const to=v('pl-to');if(to)await S.api.assignLead(l.id,to);
      m.remove();toast(to?`Assigned to ${mfirst(to)}`:'Posted to the board');S.leadSeg='board';if(S.tab!=='leads')location.hash='leads';await loadWorkspaceData()}
    catch(err){toast(err.message);c.disabled=false;c.textContent='Post lead'}})}

/* ---------- TEAM (leaderboard / wins / chat) ---------- */
function vTeam(){const n=unreadCount();
  let h=`<div class="stack"><div class="sec-h"><h2 style="font-size:28px;letter-spacing:-.03em">Team</h2></div>${seg('teamseg',S.teamSeg,[['board','Leaderboard'],['feed','Wins'],['chat','Chat',n||'']])}`;
  if(S.teamSeg==='feed')h+=vFeed();else if(S.teamSeg==='chat')h+=vChatList();else h+=vBoardLB();return h+'</div>'}
function vBoardLB(){
  if(wsSet().leaderboards===false&&!isMgr())return`<div class="card empty"><strong>Leaderboards are off</strong>Your manager turned them off for now.</div>`;
  const B={hustle:{lab:'Hustle',key:'doors',sub:r=>`${r.contacts} contacts · ${r.appts} appts`,fmt:v=>v+(v===1?' door':' doors')},
    closers:{lab:'Closers',key:'sales',sub:r=>`${r.inspections} inspections${r.inspections?' · '+Math.min(100,Math.round(r.sales/r.inspections*100))+'% close':''}`,fmt:v=>v+' sale'+(v===1?'':'s')},
    volume:{lab:'Volume',key:'volume',sub:r=>`${r.sales} sale${r.sales===1?'':'s'}`,fmt:v=>money(v)}}[S.lbBoard];
  const rows=S.lb.filter(r=>{const ro=(S.members.get(r.user_id)||{}).role;return ro==='rep'||(ro!=='office'&&(r.doors||r.sales))}).sort((a,b)=>num(b[B.key])-num(a[B.key])||b.doors-a.doors);
  const top=rows.slice(0,3),rest=rows.slice(3);const me=rows.findIndex(r=>r.user_id===S.me);
  let h=`${seg('lbboard',S.lbBoard,[['hustle','Hustle'],['closers','Closers'],['volume','Volume']])}
    <div class="chips" role="group" aria-label="Period">${[['today','Today'],['week','This week'],['month','This month']].map(([k,t])=>`<button class="chip plain" data-lbper="${k}" aria-pressed="${S.lbPer===k}">${t}</button>`).join('')}</div>`;
  if(!rows.length)return h+`<div class="card empty"><strong>No numbers yet</strong>The board fills in as the team logs doors.</div>`;
  const order=[top[1],top[0],top[2]].filter(Boolean);
  h+=`<section class="card podium">${order.map(r=>{const pos=rows.indexOf(r)+1;return `<div class="pod p${pos}${r.user_id===S.me?' me':''}"><span class="av big" style="--c:${repColor(r.user_id)}">${esc(initials(r.user_id))}</span><b class="trunc">${esc(mfirst(r.user_id))}</b><span class="pod-val num">${B.fmt(num(r[B.key]))}</span><div class="pod-step"><span>${pos}</span></div></div>`}).join('')}</section>`;
  if(me>=0){const ahead=rows[me-1];h+=`<div class="banner">${me===0?'You’re leading this board. Keep it there.':`You’re <b>#${me+1}</b> — ${B.key==='volume'?money(num(ahead[B.key])-num(rows[me][B.key])):(num(ahead[B.key])-num(rows[me][B.key]))+' '+B.key} behind ${esc(mfirst(ahead.user_id))}.`}</div>`}
  if(rest.length)h+=`<div class="card list">${rest.map((r,i)=>`<div class="li${r.user_id===S.me?' meli':''}"><span class="rank num">${i+4}</span><span class="av" style="--c:${repColor(r.user_id)}">${esc(initials(r.user_id))}</span><span class="grow"><span class="t1" style="display:block">${esc(mname(r.user_id))}</span><span class="t2">${B.sub(r)}</span></span><b class="num">${B.fmt(num(r[B.key]))}</b></div>`).join('')}</div>`;
  return h}
const REACTS=['🔥','👊','🙌','💪'];
function feedRow(f){const rs={};(f.reactions||[]).forEach(r=>{(rs[r.emoji]=rs[r.emoji]||[]).push(r.user_id)});
  const icon={sale:'🏆',streak:'🔥',milestone:'⭐',goal:'🎯',post:'📣'}[f.kind]||'📣';
  return `<div class="li feed-li"><span class="feed-ic">${icon}</span><span class="grow"><span style="display:block"><b>${esc(mname(f.user_id))}</b> ${esc(f.body)}</span><span class="t2">${agoShort(Date.parse(f.created_at))} ago</span>
    <span class="reacts">${REACTS.map(e=>{const who=rs[e]||[];return `<button class="react${who.includes(S.me)?' on':''}" data-react="${f.id}" data-emoji="${e}" aria-label="React ${e}">${e}${who.length?` <span class="num">${who.length}</span>`:''}</button>`}).join('')}</span></span></div>`}
function vFeed(){return `<div class="card pad row" style="gap:8px"><input type="text" id="shout" placeholder="Give someone a shout-out…" style="flex:1"><button class="btn pri" data-act="shout">Post</button></div>
  ${S.feed.length?`<div class="card list">${S.feed.map(feedRow).join('')}</div>`:'<div class="card empty"><strong>No wins yet</strong>Sales, streaks and milestones post here on their own.</div>'}`}
function threadTitle(th){if(th==='announce')return'Announcements';if(th==='team')return'Team chat';if(th.startsWith('dm:')){const o=th.slice(3).split(':').find(x=>x!==S.me);return mname(o)}
  if(th.startsWith('lead:')){const l=S.leads.get(th.slice(5));return l?(l.name||addr(l)):'Lead conversation'}return th}
function vChatList(){
  const last=th=>S.recent.find(m=>m.thread===th);
  const dms=[...new Set(S.recent.filter(m=>m.channel==='dm').map(m=>m.thread))];
  const row=(th,icon)=>{const m=last(th),u=unreadCount(th);return `<button class="li" data-thread="${esc(th)}"><span class="feed-ic">${icon}</span><span class="grow"><span class="t1 trunc" style="display:block">${esc(threadTitle(th))}</span><span class="t2 trunc" style="display:block">${m?esc((m.sender_id===S.me?'You':mfirst(m.sender_id))+': '+(m.body||'Photo')):'No messages yet'}</span></span>${u?`<span class="ubadge">${u}</span>`:m?`<span class="muted" style="font-size:12px">${agoShort(Date.parse(m.created_at))}</span>`:''}</button>`};
  return `<div class="card list">${row('announce','📢')}${row('team','💬')}</div>
    <div class="sec-h" style="margin-top:6px"><h2>Direct messages</h2><button class="linkbtn" data-act="newdm">+ New</button></div>
    ${dms.length?`<div class="card list">${dms.map(th=>{const o=th.slice(3).split(':').find(x=>x!==S.me);return row(th,`<span class="av" style="--c:${repColor(o)}">${esc(initials(o))}</span>`)}).join('')}</div>`:'<div class="card empty" style="padding:16px">Message a teammate privately. Managers can’t read direct messages.</div>'}`}
async function openThread(thread,opts={}){S.chat={thread,...opts};renderChat();
  try{S.threadCache[thread]=await S.api.threadMessages(S.ws.id,thread);await S.api.markRead(S.ws.id,thread);S.reads[thread]=new Date().toISOString();updateBadges()}catch(e){toast(e.message)}
  await ensureUrls((S.threadCache[thread]||[]).map(m=>m.image_path));renderChat();
  if(thread==='announce'&&isMgr()){try{S.chat.readsList=await S.api.announceReads(S.ws.id);renderChat()}catch(e){}}}
function msgBubble(m,showName){const mine=m.sender_id===S.me;if(S.blocked.includes(m.sender_id))return'';
  return `<div class="msg${mine?' mine':''}" data-msg="${m.id}">${showName&&!mine?`<span class="msg-who" style="color:${repColor(m.sender_id)}">${esc(mname(m.sender_id))}</span>`:''}
    ${m.image_path?`<img class="msg-img" src="${esc(S.urls.get(m.image_path)||'')}" alt="Photo">`:''}${m.body?`<span class="msg-body">${esc(m.body)}</span>`:''}<span class="msg-t">${new Date(m.created_at).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'})}</span></div>`}
function renderChat(){if(!S.chat){$('#layer .chat')?.remove();return}const th=S.chat.thread;const list=S.threadCache[th]||[];
  let el=$('#layer .chat');const atBottom=!el||el.querySelector('.chat-body').scrollHeight-el.querySelector('.chat-body').scrollTop-el.querySelector('.chat-body').clientHeight<80;
  const draft=el?$('#chat-in',el)?.value:'';
  if(!el){el=document.createElement('div');el.className='chat';el.setAttribute('role','dialog');el.setAttribute('aria-modal','true');$('#layer').appendChild(el)}
  const canPost=th!=='announce'||isMgr();const members=[...S.members.values()].filter(m=>m.active).length;
  const seen=S.chat.readsList&&list.length?S.chat.readsList.filter(r=>r.last_read_at>=list.at(-1).created_at&&r.user_id!==S.me).length:null;
  let lastDay='';
  el.innerHTML=`<div class="sheet-top"><div class="row gut" style="max-width:760px;margin:0 auto;padding-block:8px"><button class="iconbtn" data-act="chatclose" aria-label="Back"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg></button>
    <div class="grow"><b class="trunc" style="display:block">${esc(threadTitle(th))}</b><span class="muted" style="font-size:12px">${th==='announce'?'Managers post · everyone reads':th==='team'?members+' people':th.startsWith('dm:')?'Private':'Lead conversation'}</span></div></div></div>
    <div class="chat-body gut">${list.length?list.map(m=>{const dk=dayKey(m.created_at);const sep=dk!==lastDay?`<div class="day-sep">${new Date(m.created_at).toLocaleDateString([], {weekday:'short',month:'short',day:'numeric'})}</div>`:'';lastDay=dk;return sep+msgBubble(m,th!=='announce'&&!th.startsWith('dm:'))}).join(''):'<div class="empty">No messages yet. Say something.</div>'}
      ${seen!=null?`<div class="seen">Seen by ${seen} of ${members-1}</div>`:''}</div>
    ${canPost?`<div class="chat-compose gut"><label class="iconbtn" style="position:relative" aria-label="Attach photo"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg><input type="file" accept="image/*" id="chat-photo" style="position:absolute;inset:0;opacity:0;width:100%"></label>
      <input type="text" id="chat-in" placeholder="${th==='announce'?'Post an announcement':'Message'}" value="${esc(draft||'')}" autocomplete="off"><button class="btn pri" data-act="chatsend" aria-label="Send">Send</button></div>`:'<div class="chat-compose gut muted" style="justify-content:center;font-size:13px">Only managers post announcements.</div>'}`;
  const body=$('.chat-body',el);if(atBottom)body.scrollTop=body.scrollHeight}
async function sendChat(file){const th=S.chat.thread;const inp=$('#chat-in');const body=(inp?.value||'').trim();if(!body&&!file)return;
  const msg={channel:th==='announce'?'announce':th==='team'?'team':th.startsWith('dm:')?'dm':'lead',thread:th,body};
  if(msg.channel==='dm')msg.participants=th.slice(3).split(':');if(msg.channel==='lead')msg.lead_id=th.slice(5);
  try{if(file){const b=await downscale(file,1600);msg.image_path=await S.api.uploadFile(S.ws.id,'chat',b,'jpg');S.urls.set(msg.image_path,URL.createObjectURL(b))}
    const m=await S.api.sendMessage(S.ws.id,msg);if(inp)inp.value='';const L=(S.threadCache[th]=S.threadCache[th]||[]);if(m&&!L.find(x=>x.id===m.id))L.push(m);
    if(m&&!S.recent.find(x=>x.id===m.id))S.recent.unshift(m);renderChat();if(S.open&&th==='lead:'+S.open)renderSheet()}
  catch(e){toast(e.message)}}
function dmThread(a,b){return 'dm:'+[a,b].sort().join(':')}
function newDmModal(){const ms=[...S.members.values()].filter(m=>m.active&&m.user_id!==S.me);
  const m=modal(`<div class="row"><h2 class="grow">Message</h2><button class="iconbtn" data-c="x" aria-label="Close">✕</button></div><div class="card list" style="box-shadow:none;background:var(--sunk)">${ms.map(x=>`<button class="li" data-c="${x.user_id}"><span class="av" style="--c:${repColor(x.user_id)}">${esc(initials(x.user_id))}</span><span class="grow">${esc(x.display_name)}<span class="t2" style="display:block">${esc(roleName(x.role))}</span></span></button>`).join('')}</div>`);
  m.addEventListener('click',e=>{const c=e.target.closest('[data-c]');if(!c)return;m.remove();if(c.dataset.c!=='x')openThread(dmThread(S.me,c.dataset.c))})}
function msgActions(id){const m=Object.values(S.threadCache).flat().find(x=>x.id===id);if(!m||m.sender_id===S.me)return;
  const md=modal(`<h2>${esc(mname(m.sender_id))}</h2><p class="muted" style="margin:0">“${esc((m.body||'Photo').slice(0,120))}”</p><div class="btns"><button class="btn" data-c="dm">Message privately</button><button class="btn dng" data-c="report">Report message</button><button class="btn dng" data-c="block">Block ${esc(mfirst(m.sender_id))}</button><button class="btn" data-c="x">Cancel</button></div>`);
  md.addEventListener('click',async e=>{const c=e.target.closest('[data-c]');if(!c)return;md.remove();
    try{if(c.dataset.c==='dm'){S.chat=null;$('#layer .chat')?.remove();openThread(dmThread(S.me,m.sender_id))}
      if(c.dataset.c==='report'){await S.api.reportMessage(m.id,'Reported from app');toast('Reported to your managers')}
      if(c.dataset.c==='block'){await S.api.block(m.sender_id);S.blocked.push(m.sender_id);renderChat();toast('Blocked. You won’t see their messages.')}}catch(err){toast(err.message)}})}

/* ---------- ADMIN ---------- */
const roleName=r=>({owner:'Owner',manager:'Manager',rep:'Rep',office:'Office'})[r]||r;
function vAdmin(){let h=`<div class="stack"><div class="sec-h"><h2 style="font-size:28px;letter-spacing:-.03em">Admin</h2></div>
  <div class="chips hscroll">${[['team','People'],['rules','Lead rules'],['rates','Commissions'],['goals','Goals'],['terr','Territories'],['reports','Reports'],['company','Company']].map(([k,t])=>`<button class="chip plain" data-adminseg="${k}" aria-pressed="${S.adminSeg===k}">${t}</button>`).join('')}</div>`;
  h+=({team:aTeam,rules:aRules,rates:aRates,goals:aGoals,terr:aTerr,reports:aReports,company:aCompany}[S.adminSeg]||aTeam)();return h+'</div>'}
function aTeam(){const ms=[...S.members.values()];
  return `<section class="card pad stack" style="gap:10px"><b>Invite people</b><span class="muted" style="font-size:13.5px">Make a code and text it to them. They download the app, sign in with their email, and enter the code.</span>
    <div class="btns">${['rep','manager','office'].map(r=>`<button class="btn sm" data-invite="${r}">+ ${roleName(r)} code</button>`).join('')}</div><div id="invite-out"></div></section>
  <div class="card list">${ms.map(m=>`<div class="li"><span class="av" style="--c:${repColor(m.user_id)}">${esc(initials(m.user_id))}</span><span class="grow"><span class="t1" style="display:block">${esc(m.display_name||'(no name)')}${m.user_id===S.me?' <span class="muted">(you)</span>':''}</span><span class="t2">${m.active?'':'Deactivated · '}${esc(roleName(m.role))}</span></span>
    ${m.role==='owner'||m.user_id===S.me?'':`<select data-memrole="${m.user_id}" aria-label="Role for ${esc(m.display_name)}" style="width:auto;min-height:38px;padding:6px 8px">${['rep','manager','office'].map(r=>`<option value="${r}" ${m.role===r?'selected':''}>${roleName(r)}</option>`).join('')}</select>
      <button class="btn sm ${m.active?'dng':''}" data-memactive="${m.user_id}">${m.active?'Remove':'Restore'}</button>`}</div>`).join('')}</div>
  <p class="muted" style="font-size:12.5px;margin:0 2px">Removing someone ends their access right away. Their customers, photos and notes stay with the company; they keep only their commission history.</p>`}
function numField(id,lab,val,hint=''){return `<label class="field"><span>${lab}</span><input type="text" inputmode="decimal" id="${id}" value="${esc(val??'')}">${hint?`<small class="muted">${hint}</small>`:''}</label>`}
function toggleField(id,lab,on,hint){return `<label class="toggle"><span class="grow"><b style="display:block;font-size:14.5px">${lab}</b><small class="muted">${hint}</small></span><input type="checkbox" id="${id}" ${on?'checked':''}></label>`}
function aRules(){const s=wsSet();return `<section class="card pad stack" style="gap:12px"><b>Open Leads board</b>
  <div class="grid2">${numField('r-hrs','Contact deadline (hours)',s.claim_deadline_hours??2,'Unworked claims go back on the board')}${numField('r-cap','Claim limit',s.claim_cap??3,'Unworked claimed leads a rep can hold')}</div>
  <b>Door ownership</b>${numField('r-prot','Protection window (days)',s.protect_days??30,'A rep owns a door they pinned while they keep working it')}
  <b>What reps see</b>${toggleField('r-pins','Teammates’ pins on the map',s.teammate_pins!==false,'Status color and who pinned it — never names or phone numbers')}
  ${toggleField('r-lb','Leaderboards',s.leaderboards!==false,'Doors, sales and contract volume. Commissions are never shown.')}
  <button class="btn pri" data-savews="rules">Save rules</button></section>`}
function aRates(){const r=wsSet().rates||{self:{},company:{}};const ms=[...S.members.values()].filter(m=>['rep','manager','owner'].includes(m.role)&&m.active);
  const row=(src,lab)=>`<b>${lab}</b><div class="grid3">${JOBTYPES.map(t=>numField(`rt-${src}-${t}`,t+' %',(r[src]||{})[t]??'')).join('')}</div>`;
  return `<section class="card pad stack" style="gap:12px">${row('self','Self-generated leads (rep knocked it)')}${row('company','Company leads (office posted it)')}<button class="btn pri" data-savews="rates">Save rates</button></section>
  <section class="card pad stack" style="gap:10px"><b>Per-rep override</b><span class="muted" style="font-size:13px">Leave blank to use the rates above.</span>
  ${ms.map(m=>`<div class="row"><span class="grow trunc">${esc(m.display_name)}</span><input type="text" inputmode="decimal" data-reprate="${m.user_id}" value="${esc((m.prefs||{}).rate??'')}" placeholder="—" style="width:84px" aria-label="Override % for ${esc(m.display_name)}"><span class="muted">%</span></div>`).join('')}
  <button class="btn" data-savews="reprates">Save overrides</button></section>`}
function aGoals(){const g=wsSet().team_goal||{};return `<section class="card pad stack" style="gap:12px"><b>Team goal</b><span class="muted" style="font-size:13px">Everyone sees one shared bar on their Home screen.</span>
  <label class="field"><span>Name</span><input type="text" id="g-label" value="${esc(g.label||'')}" placeholder="500 doors in November"></label>
  <div class="grid2"><label class="field"><span>Counts</span><select id="g-metric">${[['doors','Doors'],['appts','Appointments'],['sales','Sales'],['volume','Contract $']].map(([k,t])=>`<option value="${k}" ${g.metric===k?'selected':''}>${t}</option>`).join('')}</select></label>${numField('g-target','Target',g.target??'')}</div>
  ${numField('g-rep','Default monthly commission goal per rep ($)',wsSet().goal??'')}
  <button class="btn pri" data-savews="goals">Save goals</button>${g.target?'<button class="btn dng" data-savews="cleargoal">Clear team goal</button>':''}</section>`}
function aTerr(){return `<section class="card pad stack" style="gap:10px"><b>Territories</b><span class="muted" style="font-size:13px">Draw an area on the map and assign reps to it. Everyone sees the outlines.</span>
  <button class="btn pri" data-act="drawterr">+ Draw a territory on the map</button></section>
  ${S.terr.length?`<div class="card list">${S.terr.map(t=>`<div class="li"><span class="sw-big" style="background:${esc(t.color)}"></span><span class="grow"><span class="t1" style="display:block">${esc(t.name)}</span><span class="t2">${(t.rep_ids||[]).map(id=>esc(mfirst(id))).join(', ')||'No reps assigned'}</span></span><button class="btn sm" data-editterr="${t.id}">Edit</button></div>`).join('')}</div>`:''}`}
function aReports(){const M=S.lbMonth;const L=leadsArr().filter(l=>l.origin==='company'&&l.claimed_at);
  const avg=a=>a.length?Math.round(a.reduce((x,y)=>x+y,0)/a.length):null;
  const rows=M.filter(r=>(S.members.get(r.user_id)||{}).role!=='office').map(r=>{const mine=L.filter(l=>l.owner_id===r.user_id);
    const toClaim=avg(mine.filter(l=>l.posted_at).map(l=>(Date.parse(l.claimed_at)-Date.parse(l.posted_at))/60000));
    const toContact=avg(mine.filter(l=>l.contacted_at).map(l=>(Date.parse(l.contacted_at)-Date.parse(l.claimed_at))/60000));
    return{...r,office:mine.length,toClaim,toContact}}).sort((a,b)=>b.volume-a.volume);
  const mins=v=>v==null?'—':v<60?v+'m':Math.round(v/60*10)/10+'h';
  return `<section class="card"><div class="pad" style="padding-bottom:0"><b>${new Date().toLocaleDateString([], {month:'long',year:'numeric'})}</b></div><div class="scroll-x"><table class="tbl"><thead><tr><th>Rep</th><th class="r">Doors</th><th class="r">Cont.</th><th class="r">Appts</th><th class="r">Insp.</th><th class="r">Sales</th><th class="r">Close</th><th class="r">Volume</th><th class="r">Office leads</th><th class="r">To claim</th><th class="r">To contact</th></tr></thead><tbody>
  ${rows.map(r=>`<tr><td>${esc(r.display_name)}</td><td class="r">${r.doors}</td><td class="r">${r.contacts}</td><td class="r">${r.appts}</td><td class="r">${r.inspections}</td><td class="r">${r.sales}</td><td class="r">${r.inspections?Math.min(100,Math.round(r.sales/r.inspections*100))+'%':'—'}</td><td class="r"><b>${money(r.volume)}</b></td><td class="r">${r.office}</td><td class="r">${mins(r.toClaim)}</td><td class="r">${mins(r.toContact)}</td></tr>`).join('')}
  </tbody></table></div></section><div class="btns"><button class="btn" data-act="exportteam">Export team leads (CSV)</button></div>`}
function aCompany(){return `<section class="card pad stack" style="gap:12px"><label class="field"><span>Company name (shows on inspection reports)</span><input type="text" id="c-name" value="${esc(S.ws.name)}"></label>
  <label class="field"><span>Contract terms shown at signing</span><textarea id="c-terms">${esc(wsSet().terms||'')}</textarea></label><button class="btn pri" data-savews="company">Save</button></section>
  ${S.role==='owner'?`<section class="card pad stack" style="gap:8px"><b>Message records</b><span class="muted" style="font-size:13px">Only the account owner can export every message, including direct messages, for a legal dispute. Reps are told this in the app.</span><button class="btn" data-act="exportmsgs">Export all messages</button></section>`:''}`}
async function saveWs(kind){const s={...wsSet()};const v=id=>$('#'+id)?.value.trim();
  if(kind==='rules'){s.claim_deadline_hours=num(v('r-hrs'))||2;s.claim_cap=Math.max(1,Math.round(num(v('r-cap'))||3));s.protect_days=Math.max(1,Math.round(num(v('r-prot'))||30));s.teammate_pins=$('#r-pins').checked;s.leaderboards=$('#r-lb').checked}
  if(kind==='rates'){s.rates={self:{},company:{}};for(const src of['self','company'])for(const t of JOBTYPES)s.rates[src][t]=num(v(`rt-${src}-${t}`))}
  if(kind==='goals'){s.team_goal=num(v('g-target'))?{label:v('g-label')||'Team goal',metric:$('#g-metric').value,target:num(v('g-target'))}:null;s.goal=num(v('g-rep'))}
  if(kind==='cleargoal')s.team_goal=null;
  if(kind==='company')s.terms=v('c-terms');
  if(kind==='reprates'){try{for(const inp of $$('[data-reprate]')){const m=S.members.get(inp.dataset.reprate);const val=inp.value.trim();const prefs={...(m.prefs||{}),rate:val===''?null:num(val)};await S.api.updateMember(S.ws.id,m.user_id,{prefs});m.prefs=prefs}toast('Overrides saved')}catch(e){toast(e.message)}return}
  try{const patch={settings:s};if(kind==='company'&&v('c-name'))patch.name=v('c-name');await S.api.updateWorkspace(S.ws.id,patch);Object.assign(S.ws,patch);applyIdentity();toast('Saved');if(kind==='company')$('#wsname').textContent=S.ws.name;render()}catch(e){toast(e.message)}}
function terrModal(t){const reps=[...S.members.values()].filter(m=>m.active&&['rep','manager','owner'].includes(m.role));const cols=['#2F6BFF','#12A150','#E58A00','#8B5CF6','#E5372B','#0EA5B7'];
  const m=modal(`<div class="row"><h2 class="grow">${t.id?'Edit':'New'} territory</h2><button class="iconbtn" data-c="x" aria-label="Close">✕</button></div>
    <label class="field"><span>Name</span><input type="text" id="t-name" value="${esc(t.name||'')}" placeholder="East side"></label>
    <div class="row" style="gap:8px">${cols.map(c=>`<button class="swatch" data-col="${c}" aria-pressed="${(t.color||cols[0])===c}" style="background:${c}" aria-label="Color"></button>`).join('')}</div>
    <div class="label">Reps working it</div><div class="chips">${reps.map(r=>`<button class="chip plain" data-trep="${r.user_id}" aria-pressed="${(t.rep_ids||[]).includes(r.user_id)}">${esc(r.display_name)}</button>`).join('')}</div>
    <div class="btns">${t.id?'<button class="btn dng" data-c="del">Delete</button><button class="btn" data-c="redraw">Redraw on map</button>':''}<button class="btn pri grow" data-c="save">Save</button></div>`);
  let color=t.color||cols[0];const sel=new Set(t.rep_ids||[]);
  m.addEventListener('click',async e=>{const col=e.target.closest('[data-col]');if(col){color=col.dataset.col;$$('[data-col]',m).forEach(b=>b.setAttribute('aria-pressed',b===col));return}
    const tr=e.target.closest('[data-trep]');if(tr){const id=tr.dataset.trep;sel.has(id)?sel.delete(id):sel.add(id);tr.setAttribute('aria-pressed',sel.has(id));return}
    const c=e.target.closest('[data-c]');if(!c)return;if(c.dataset.c==='x'){m.remove();return}
    try{if(c.dataset.c==='del'){if(!(await confirmBox('Delete this territory?')))return;await S.api.deleteTerritory(t.id)}
      if(c.dataset.c==='redraw'){m.remove();S.terrDraft={...t,points:[]};S.mapMode='terr';location.hash='map';render();return}
      if(c.dataset.c==='save'){const name=$('#t-name',m).value.trim()||'Territory';await S.api.saveTerritory(S.ws.id,{...t,name,color,rep_ids:[...sel]})}
      m.remove();S.terr=await S.api.territories(S.ws.id);toast('Territory saved');render()}catch(err){toast(err.message)}})}

/* ---------- settings (personal) ---------- */
function settingsModal(){const s=S.settings;const me=S.members.get(S.me)||{};
  const m=modal(`<div class="row"><h2 class="grow">Settings</h2><button class="iconbtn" data-c="x" aria-label="Close">✕</button></div>
    <div class="grid2"><label class="field"><span>Your name</span><input type="text" id="s-name" value="${esc(me.display_name||'')}"></label><label class="field"><span>Your phone</span><input type="tel" id="s-phone" value="${esc(me.phone||'')}"></label></div>
    <label class="field"><span>Default city</span><input type="text" id="s-city" value="${esc(s.city)}"></label>
    ${isCompany()?'':`<div class="label">Commission rates</div><div class="grid3">${JOBTYPES.map(t=>`<label class="field"><span>${t} %</span><input type="text" inputmode="decimal" id="s-r-${t}" value="${esc(((wsSet().rates||{}).self||{})[t]??10)}"></label>`).join('')}</div>`}
    ${S.role!=='office'?`<label class="field"><span>My monthly commission goal $</span><input type="text" inputmode="decimal" id="s-goal" value="${esc(s.goal)}"></label>`:''}
    <label class="field"><span>Mapbox key (optional — sharper satellite)</span><input type="text" id="s-mapboxKey" value="${esc(s.mapboxKey||'')}" placeholder="pk.…" autocomplete="off" autocapitalize="off" spellcheck="false"></label>
    ${colorsHTML(s)}
    <button class="btn pri" data-c="save">Save</button>
    <hr class="hr">
    <div class="label">Account</div>
    <div class="card list" style="box-shadow:none;background:var(--sunk)">${S.wsList.map(w=>`<button class="li" data-c="ws:${w.id}"><span class="grow"><span class="t1" style="display:block">${esc(w.kind==='company'?w.name:'My solo account')}</span><span class="t2">${esc(roleName(w.role))}${w.kind==='individual'?' · individual':''}</span></span>${w.id===S.ws.id?'<b style="color:var(--accent)">✓</b>':''}</button>`).join('')}
      <button class="li" data-c="addws"><span class="grow" style="color:var(--accent);font-weight:700">+ Join or start another account</span></button></div>
    <div class="btns"><button class="btn sm" data-c="csv">Export my leads (CSV)</button><button class="btn sm" data-c="json">Backup (with photos)</button></div>
    ${S.api.mode==='demo'?`<div class="label">Demo — view the app as</div><div class="chips">${S.api.users.map(u=>`<button class="chip plain" data-c="as:${u.user_id}" aria-pressed="${S.me===u.user_id}">${esc(u.display_name.split(' ')[0])} · ${esc(u.title||roleName(u.role))}</button>`).join('')}</div><button class="btn sm" data-c="resetdemo">Reset demo data</button>`
      :`<span class="muted" style="font-size:13px">Signed in as ${esc(S.email)}</span><button class="btn sm" data-c="signout">Sign out</button>`}`);
  bindColors(m);
  m.addEventListener('click',async e=>{const tp=e.target.closest('[data-theme-pick]');if(tp){s.theme=tp.dataset.themePick;applyTheme();saveSettings();$$('[data-theme-pick]',m).forEach(b=>b.setAttribute('aria-checked',b===tp));return}
    const c=e.target.closest('[data-c]');if(!c)return;const k=c.dataset.c;
    if(k==='x'){m.remove();return}
    if(k==='save'){const old=s.mapboxKey||'';s.city=$('#s-city',m).value.trim();if($('#s-goal',m)){s.goal=num($('#s-goal',m).value);s.goalSet=true}s.mapboxKey=$('#s-mapboxKey',m).value.trim();saveSettings();
      if(s.mapboxKey!==old&&MV.map){MV.map.remove();MV.map=null;MV.host=null;MV.warned=0}
      try{const nm=$('#s-name',m).value.trim(),ph=$('#s-phone',m).value.trim();if(nm!==me.display_name||ph!==me.phone){await S.api.updateMember(S.ws.id,S.me,{display_name:nm,phone:ph});me.display_name=nm;me.phone=ph;applyIdentity()}
        if(!isCompany()){const rs={...wsSet()};rs.rates={...(rs.rates||{}),self:Object.fromEntries(JOBTYPES.map(t=>[t,num($('#s-r-'+t,m).value)]))};await S.api.updateWorkspace(S.ws.id,{settings:rs});S.ws.settings=rs}}catch(err){toast(err.message)}
      m.remove();render();toast('Saved');return}
    if(k.startsWith('ws:')){m.remove();await enterApp(k.slice(3));return}
    if(k==='addws'){m.remove();showOnboard();return}
    if(k==='csv')exportCSV();if(k==='json')exportJSON();
    if(k.startsWith('as:')){S.api.switchUser(k.slice(3));S.me=k.slice(3);m.remove();await enterApp();toast('Now viewing as '+(S.members.get(S.me)||{}).display_name);return}
    if(k==='resetdemo'){if(!(await confirmBox('Put the demo company back to how it started?','Reset')))return;S.api.reset();Object.keys(localStorage).filter(x=>x.startsWith('rlt.')).forEach(x=>localStorage.removeItem(x));location.reload()}
    if(k==='signout'){await S.api.signOut();location.reload()}})}

function pinIcon(l,on,opt={}){const st=SMAP[l.status]||SMAP['Not Home'];const ri=RT.ids.indexOf(l.id);
  const rb=ri>=0&&(S.mapMode==='route'||RT.ids.length)?`<em class="${ri<RT.idx?'past':ri===RT.idx?'cur':''}">${ri+1}</em>`:'';
  const col=S.colorBy==='rep'&&l.owner_id?repColor(l.owner_id):sv(l.status);const hol=st.hollow&&S.colorBy!=='rep';
  const label=opt.team?initials(l.owner_id||l.created_by):String(l.num||'•').slice(0,4);
  return L.divIcon({className:'mk-wrap',iconSize:[34,44],iconAnchor:[17,41],
    html:`<div class="mk${hol?' hol':''}${on?' on':''}${opt.team?' tm':''}" style="--c:${col}"><b></b><span>${esc(label)}</span>${l.ref?'<i></i>':''}${rb}</div>`})}
function openIcon(){return L.divIcon({className:'mk-wrap',iconSize:[34,44],iconAnchor:[17,41],html:'<div class="mk openmk" style="--c:var(--s-sched)"><b></b><span>NEW</span></div>'})}
function refreshPins(){if(!MV.map)return;MV.pins.clearLayers();
  if(MV.terrLayer){MV.map.removeLayer(MV.terrLayer);MV.terrLayer=null}
  if(isCompany()&&(S.terr.length||S.terrDraft)){MV.terrLayer=L.layerGroup().addTo(MV.map);
    for(const t of S.terr){if(S.terrDraft&&S.terrDraft.id===t.id)continue;if((t.points||[]).length>2)L.polygon(t.points,{color:t.color,weight:2,fillOpacity:.07,interactive:false}).addTo(MV.terrLayer).bindTooltip(t.name,{permanent:false,direction:'center'})}
    if(S.terrDraft&&S.terrDraft.points.length){const p=S.terrDraft.points;(p.length>2?L.polygon(p,{color:'#F2541B',weight:3,dashArray:'6 6',fillOpacity:.1}):L.polyline(p,{color:'#F2541B',weight:3,dashArray:'6 6'})).addTo(MV.terrLayer);p.forEach(x=>L.circleMarker(x,{radius:6,color:'#fff',weight:2,fillColor:'#F2541B',fillOpacity:1}).addTo(MV.terrLayer))}}
  const click=(id)=>ev=>{L.DomEvent.stopPropagation(ev);
    if(S.mapMode==='route'){if(!S.leads.has(id)){toast('Only your own leads go on your route');return}
      if(RT.ids.includes(id)){const i=RT.ids.indexOf(id);RT.ids.splice(i,1);if(i<RT.idx)RT.idx--;toast('Removed from route')}else{RT.ids.push(id);toast(`Stop ${RT.ids.length}: ${addr(S.leads.get(id))}`)}saveRoute();buildRoute({optimize:false});return}
    if(S.mapMode==='terr')return;S.selPin=id;S.pinHist=null;render();loadPinHistory(id)};
  for(const l of leadsArr()){if(!l.geo||l.pool)continue;const on=S.selPin===l.id;
    L.marker([l.geo.lat,l.geo.lng],{icon:pinIcon(l,on,{team:viewAll()&&l.owner_id&&l.owner_id!==S.me}),zIndexOffset:on?1000:(l.owner_id===S.me?200:0),keyboard:false}).on('click',click(l.id)).addTo(MV.pins)}
  if(isCompany()){for(const p of S.pins){if(S.leads.has(p.id)||p.lat==null)continue;const on=S.selPin===p.id;
      L.marker([p.lat,p.lng],{icon:pinIcon({...p,num:p.num},on,{team:true}),zIndexOffset:on?1000:-100,keyboard:false,opacity:on?1:.85}).on('click',click(p.id)).addTo(MV.pins)}
    for(const o of S.openBoard){if(o.lat==null)continue;L.marker([o.lat,o.lng],{icon:openIcon(),zIndexOffset:500,keyboard:false}).on('click',ev=>{L.DomEvent.stopPropagation(ev);S.selPin='open:'+o.id;render()}).addTo(MV.pins)}}
  drawRoute();drawZones();drawStorms()}
async function loadPinHistory(id){try{const h=await S.api.pinHistory(id);if(S.selPin===id){S.pinHist=h;render()}}catch(e){}}
function gpsCheck(k,geo){if(!k.gps||!geo)return'';const d=hav(k.gps,geo)*5280;return d<250?'<span class="gps ok" title="Logged at the door">📍 at the door</span>':`<span class="gps far" title="Where the rep was when they logged it">⚠ ${d<5280?Math.round(d)+' ft':(d/5280).toFixed(1)+' mi'} away</span>`}
function histHTML(h,geo){if(!h)return'<div class="muted" style="font-size:12.5px">Loading history…</div>';
  const ks=(h.knocks||[]).slice().sort((a,b)=>b.t-a.t).slice(0,6);
  return `<div class="pin-hist">${ks.map(k=>`<div><span class="dotc" style="background:${sv(k.r)}"></span><b>${esc(k.r)}</b> · ${esc(mfirst(k.by))} · ${esc(fmtStamp(k.t))} ${viewAll()?gpsCheck(k,geo):''}</div>`).join('')}</div>`}
function mapHTML(){
  const mode=S.mapMode||'browse',selId=S.selPin;const sel=selId&&!String(selId).startsWith('open:')&&S.leads.get(selId);
  const pin=selId&&!sel&&!String(selId).startsWith('open:')?S.pins.find(p=>p.id===selId):null;
  const open=selId&&String(selId).startsWith('open:')?S.openBoard.find(o=>'open:'+o.id===selId):null;
  const unplaced=myLeads().filter(l=>!l.geo).length;
  const hint=mode==='skip'?'Tap around the area to outline it':mode==='pin'?'Tap a roof to pin that house':mode==='route'?'Tap your pins to add or remove stops':mode==='terr'?'Tap the map to outline the territory':isCompany()?'Faded pins are teammates’ doors':'Tap a pin to update it';
  const mine=sel&&(sel.owner_id===S.me||isMgr());
  let h=`<div class="mapwrap" id="mapwrap"><div id="mapslot" class="mapslot"></div>
    <div class="map-tools">${mode==='terr'?'':`<div class="seg seg4" role="tablist" aria-label="Map mode">
      <button role="tab" data-mm="browse" aria-selected="${mode==='browse'}">Browse</button><button role="tab" data-mm="pin" aria-selected="${mode==='pin'}">Pin</button><button role="tab" data-mm="route" aria-selected="${mode==='route'}">Route${RT.ids.length?` <span class="num" style="opacity:.6">${RT.ids.length}</span>`:''}</button><button role="tab" data-mm="skip" aria-selected="${mode==='skip'}">Skip</button></div>`}</div>
    <div class="map-zoom">
      <button data-mz="gps" aria-label="Show my location" class="${MV.gps.watch?'gps-on':''}"><svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M21 3 3 10.5l7.5 3L13.5 21z"/></svg></button>
      <button data-mz="in" aria-label="Zoom in">+</button><button data-mz="out" aria-label="Zoom out">−</button>
      <button data-mz="layer" aria-label="Change map style" style="font-size:10.5px;font-weight:800">${{hybrid:'HYB',sat:'SAT',street:'MAP'}[MV.base]||'HYB'}</button>
      <button data-mz="storm" aria-label="${S.settings.stormLayer?'Hide':'Show'} storm reports" aria-pressed="${!!S.settings.stormLayer}" class="mk-storm-btn${S.settings.stormLayer?' on':''}"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 16a5 5 0 1 1 1.2-9.9A6 6 0 0 1 19.5 9 4 4 0 0 1 18 16.9"/><path d="m13 12-3 5h4l-3 5"/></svg></button>
      ${viewAll()?`<button data-mz="colorby" aria-label="Color pins by ${S.colorBy==='rep'?'status':'rep'}" title="Color by ${S.colorBy==='rep'?'status':'rep'}" style="font-size:10.5px;font-weight:800">${S.colorBy==='rep'?'REP':'STAT'}</button>`:''}</div>
    ${!window.L?`<div class="map-empty"><b>Map can’t load</b><span>Connect to the internet once so the map can download.</span></div>`:''}
    ${!selId&&ST.sel&&S.settings.stormLayer&&!['route','terr'].includes(mode)?stormCard():''}
    <div class="map-hint">${hint}${unplaced&&mode!=='terr'?` · ${unplaced} not on map`:''}</div>
    ${mode==='route'?routeCard():''}${mode==='skip'?skipCard():''}${mode!=='skip'&&S.selZone&&!selId?zoneCard():''}
    ${mode==='terr'?`<div class="map-pop card"><b>${S.terrDraft&&S.terrDraft.id?'Redraw':'New'} territory · ${S.terrDraft?S.terrDraft.points.length:0} points</b><span class="muted" style="font-size:13px">Tap around the area’s edge. Three points or more makes a shape.</span><div class="btns"><button class="btn" data-terr="undo">Undo</button><button class="btn" data-terr="cancel">Cancel</button><button class="btn pri grow" data-terr="done" ${S.terrDraft&&S.terrDraft.points.length>2?'':'disabled'}>Done</button></div></div>`:''}
    ${MV.gps.pos&&!selId&&!['route','terr'].includes(mode)?`<button class="btn pri pinme" data-act="pinme"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" aria-hidden="true"><path d="M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12z"/><circle cx="12" cy="9" r="2.5"/></svg>Pin where I’m standing</button>`:''}`;
  const attrib=(created_by,created_at,owner)=>`<div class="attrib">Pinned by <b>${esc(mname(created_by))}</b> · ${esc(fmtDate(created_at))}${owner&&owner!==created_by?` · worked by <b>${esc(mname(owner))}</b>`:''}</div>`;
  if(sel&&!['route','terr'].includes(mode))h+=`<div class="map-pop card"><div class="row"><span class="grow"><span class="t1 trunc" style="display:block;font-weight:800">${star(sel)}${esc(sel.name||addr(sel))}</span><span class="muted trunc" style="display:block;font-size:13px">${esc(sel.name?addr(sel)+' · ':'')}${esc(sel.status)}${sel.followAt?' · '+esc(fmtWhen(sel.followAt)):''}</span></span>
      <button class="iconbtn" data-act="popclose" aria-label="Close">✕</button></div>
    ${isCompany()?attrib(sel.created_by,sel.created||sel.created_at,sel.owner_id):''}${isCompany()?histHTML(S.pinHist,sel.geo):''}
    ${mine?`<div class="chips hscroll">${KNOCK_RESULTS.map(k=>`<button class="chip" style="--c:${sv(k)}" data-qs="${esc(k)}" aria-pressed="${sel.status===k}"><span class="sw"></span>${esc(k)}</button>`).join('')}</div>`:''}
    <div class="btns"><button class="btn pri grow" data-open="${sel.id}">Open lead</button><a class="btn" target="_blank" rel="noopener" href="https://maps.apple.com/?daddr=${sel.geo?sel.geo.lat+','+sel.geo.lng:encodeURIComponent(fullAddr(sel))}">Drive</a>${mine?'<button class="btn" data-act="unpin">Move pin</button>':''}</div></div>`;
  if(pin&&!['route','terr'].includes(mode)){const prot=pin.protected_until&&Date.parse(pin.protected_until)>Date.now();
    h+=`<div class="map-pop card"><div class="row"><span class="grow"><span class="t1" style="display:block;font-weight:800">${esc(pin.num?pin.num+' ':'')}${esc(pin.street||'Teammate’s door')}</span><span class="muted" style="font-size:13px">${pill(pin.status)}</span></span><button class="iconbtn" data-act="popclose" aria-label="Close">✕</button></div>
      ${attrib(pin.created_by,pin.created_at,pin.owner_id)}${histHTML(S.pinHist,{lat:pin.lat,lng:pin.lng})}
      <div class="muted" style="font-size:12.5px">${prot?`${esc(mfirst(pin.owner_id))}’s door until ${esc(fmtDate(pin.protected_until))}. Message them if you’re close by.`:'Nobody has worked this door lately — you can take it over.'}</div>
      <div class="btns"><button class="btn" data-dmuser="${pin.owner_id}">Message ${esc(mfirst(pin.owner_id))}</button>${!prot&&S.role!=='office'?`<button class="btn pri grow" data-takeover="${pin.id}">Take over this door</button>`:''}</div></div>`}
  if(open&&!['route','terr'].includes(mode))h+=`<div class="map-pop card"><div class="row"><span class="grow"><span class="job-tag">${esc(open.job||'Inspection')}</span>${open.insurance?' <span class="job-tag ins">Insurance</span>':''}<b style="display:block;margin-top:6px">${esc(open.street)}</b><span class="muted" style="font-size:13px">${esc(open.window_text||'')} · posted ${agoShort(Date.parse(open.posted_at))} ago</span></span><button class="iconbtn" data-act="popclose" aria-label="Close">✕</button></div>
    ${open.notes?`<div style="font-size:14px">${esc(open.notes)}</div>`:''}<div class="btns">${S.role!=='office'?`<button class="btn pri grow" data-claim="${open.id}">Claim this lead</button>`:''}<button class="btn" data-gotoboard="1">Open board</button></div></div>`;
  return h+'</div>'}
function addTerrPoint(ll){if(!S.terrDraft)S.terrDraft={points:[]};S.terrDraft.points.push([+ll.lat.toFixed(6),+ll.lng.toFixed(6)]);render()}

/* ---------- lead sheet: team parts ---------- */
function companyBar(l){if(!isCompany())return'';
  const reps=[...S.members.values()].filter(m=>m.active&&['rep','manager','owner'].includes(m.role));
  const origin=l.origin==='company'?`<span class="job-tag">Office lead</span>`:'';
  let h=`<div class="cbar card pad"><div class="row" style="flex-wrap:wrap;gap:6px">${origin}<span class="muted" style="font-size:13px">Pinned by <b>${esc(mname(l.created_by))}</b> · ${esc(fmtDate(l.created))}</span></div>`;
  if(isMgr())h+=`<label class="field"><span>Worked by</span><select data-assign="${l.id}">${l.owner_id?'':'<option value="">On the open board</option>'}${reps.map(r=>`<option value="${r.user_id}" ${l.owner_id===r.user_id?'selected':''}>${esc(r.display_name)}</option>`).join('')}${l.owner_id&&l.origin==='company'?'<option value="__board">Send back to the board</option>':''}</select></label>`;
  else if(l.owner_id&&l.owner_id!==S.me)h+=`<div style="font-size:14px">Worked by <b>${esc(mname(l.owner_id))}</b></div>`;
  if(l.owner_id===S.me&&l.origin==='company'&&!isMgr())h+=`<button class="btn sm" data-act="releaselead">Give back to the board</button>`;
  if(l.owner_id===S.me&&l.claimed_at&&!l.contacted_at){const hrs=num(wsSet().claim_deadline_hours)||2;const left=hrs*3600e3-(Date.now()-Date.parse(l.claimed_at));
    h+=`<div class="banner" style="background:color-mix(in srgb,var(--s-follow) 12%,var(--surface))">Contact them ${left>0?'within '+Math.ceil(left/60e3)+' min':'now'} — log a call, note or status and it counts.</div>`}
  return h+'</div>'}
function threadHTML(l){const th='lead:'+l.id;const list=S.threadCache[th];
  return `${list?list.length?`<div class="mini-thread">${list.slice(-6).map(m=>`<div class="mt-row${m.sender_id===S.me?' mine':''}"><b style="color:${repColor(m.sender_id)}">${esc(mfirst(m.sender_id))}</b> ${m.image_path?'📷 ':''}${esc(m.body)} <span class="muted">${agoShort(Date.parse(m.created_at))}</span></div>`).join('')}</div>`:'<span class="muted" style="font-size:13.5px">Talk about this job with the office and your manager. Everything stays with the lead.</span>':'<span class="muted">Loading…</span>'}
    <div><button class="btn sm" data-thread="${esc(th)}">${list&&list.length?'Open conversation':'Start conversation'}</button></div>`}
async function afterSheet(l){const any=await ensureUrls(leadFilePaths(l));
  if(isCompany()&&!S.threadCache['lead:'+l.id]){try{S.threadCache['lead:'+l.id]=await S.api.threadMessages(S.ws.id,'lead:'+l.id)}catch(e){S.threadCache['lead:'+l.id]=[]}if(S.open===l.id&&!sheetBusy())renderSheet(false,true);return}
  if(any&&S.open===l.id&&!sheetBusy())renderSheet(false,true)}

/* ---------- feed auto-posts ---------- */
function autoFeed(kind,body,amount){if(!isCompany())return;S.api.postFeed(S.ws.id,{kind,body,amount:amount??null}).then(loadFeed).catch(()=>{})}
function checkStreak(){const s=calcStreak();const key='streakPosted';const done=S.settings[key]||{};
  if([5,10,20,30,50,100].includes(s)&&!done[s+':'+todayKey()]){done[s+':'+todayKey()]=1;S.settings[key]=done;saveSettings();autoFeed('streak',`hit a ${s}-day knocking streak`)}}

/* ---------- team event handlers (run before the field-app handlers) ---------- */
document.addEventListener('click',async e=>{const t=e.target;
  if(await authClick(t)){e.stopImmediatePropagation();return}
  const stop=()=>e.stopImmediatePropagation();
  const segs=[['leadseg','leadSeg'],['teamseg','teamSeg'],['adminseg','adminSeg'],['lbboard','lbBoard']];
  for(const [attr,key] of segs){const el=t.closest(`[data-${attr}]`);if(el){S[key]=el.dataset[attr];const tab=el.dataset.tab||{leadseg:'leads',teamseg:'team',adminseg:'admin',lbboard:'team'}[attr];stop();
      if(attr==='teamseg'&&S[key]==='board')loadTeamNumbers();if(attr==='teamseg'&&S[key]==='feed')loadFeed();if(attr==='teamseg'&&S[key]==='chat')loadMessages();
      if(location.hash.slice(1)!==tab)location.hash=tab;else render();return}}
  const lp=t.closest('[data-lbper]');if(lp){stop();S.lbPer=lp.dataset.lbper;loadTeamNumbers();render();return}
  if(t.closest('[data-gotoboard]')){stop();S.leadSeg='board';S.selPin=null;if(location.hash!=='#leads')location.hash='leads';else render();refreshBoard();return}
  const cl=t.closest('[data-claim]');if(cl){stop();cl.disabled=true;try{const r=await S.api.claimLead(cl.dataset.claim);
      if(r==='ok'){toast('It’s yours — call them now');await loadWorkspaceData();S.selPin=null;openLead(cl.dataset.claim)}
      else if(r==='cap'){toast(`Work the ${num(wsSet().claim_cap)||3} leads you already claimed first`);cl.disabled=false}
      else{toast('Someone else just claimed it');refreshBoard()}}catch(err){toast(err.message);cl.disabled=false}return}
  const dp=t.closest('[data-delpool]');if(dp){stop();if(!(await confirmBox('Delete this lead from the board?')))return;try{await S.api.deleteLead(S.ws.id,dp.dataset.delpool);S.leads.delete(dp.dataset.delpool);persist();refreshBoard()}catch(err){toast(err.message)}return}
  if(t.closest('[data-act="postlead"]')){stop();postLeadModal();return}
  const rc=t.closest('[data-react]');if(rc){stop();try{await S.api.toggleReaction(rc.dataset.react,rc.dataset.emoji);await loadFeed()}catch(err){toast(err.message)}return}
  if(t.closest('[data-act="shout"]')){stop();const v=$('#shout').value.trim();if(!v)return;await S.api.postFeed(S.ws.id,{kind:'post',body:v});$('#shout').value='';loadFeed();return}
  const th=t.closest('[data-thread]');if(th){stop();openThread(th.dataset.thread);return}
  if(t.closest('[data-act="newdm"]')){stop();newDmModal();return}
  const du=t.closest('[data-dmuser]');if(du){stop();S.selPin=null;openThread(dmThread(S.me,du.dataset.dmuser));return}
  if(t.closest('[data-act="chatclose"]')){stop();S.chat=null;renderChat();if(S.tab==='team')render();return}
  if(t.closest('[data-act="chatsend"]')){stop();sendChat();return}
  const mg=t.closest('.chat [data-msg]');if(mg){stop();msgActions(mg.dataset.msg);return}
  const inv=t.closest('[data-invite]');if(inv){stop();try{const code=await S.api.createInvite(S.ws.id,inv.dataset.invite);const url=location.origin+location.pathname;
      const msg=`You’re invited to ${S.ws.name} on Ridgeline as a ${roleName(inv.dataset.invite).toLowerCase()}.\n\n1. Open ${url}?join=${code} on your iPhone in Safari\n2. Tap Share → Add to Home Screen, then open Ridgeline from your home screen\n3. Sign in with your email and enter invite code ${code}`;
      $('#invite-out').innerHTML=`<div class="invite"><span class="label">${esc(roleName(inv.dataset.invite))} code</span><b class="code">${esc(code)}</b><textarea readonly style="min-height:90px">${esc(msg)}</textarea><button class="btn sm pri" data-copy="${esc(msg)}">Copy invite text</button></div>`}catch(err){toast(err.message)}return}
  const ma=t.closest('[data-memactive]');if(ma){stop();const m=S.members.get(ma.dataset.memactive);if(m.active&&!(await confirmBox(`Remove ${m.display_name}? They lose access right away. Their leads stay with the company.`,'Remove')))return;
    try{await S.api.updateMember(S.ws.id,m.user_id,{active:!m.active});m.active=!m.active;render()}catch(err){toast(err.message)}return}
  const sw=t.closest('[data-savews]');if(sw){stop();saveWs(sw.dataset.savews);return}
  if(t.closest('[data-act="drawterr"]')){stop();S.terrDraft={points:[]};S.mapMode='terr';S.selPin=null;location.hash='map';return}
  const et=t.closest('[data-editterr]');if(et){stop();terrModal(S.terr.find(x=>x.id===et.dataset.editterr));return}
  const tr=t.closest('[data-terr]');if(tr){stop();const k=tr.dataset.terr;if(k==='undo'&&S.terrDraft){S.terrDraft.points.pop();render()}
    if(k==='cancel'){S.terrDraft=null;S.mapMode='browse';render()}
    if(k==='done'&&S.terrDraft){const d=S.terrDraft;S.terrDraft=null;S.mapMode='browse';render();terrModal(d)}return}
  const to=t.closest('[data-takeover]');if(to){stop();try{const r=await S.api.takeOverDoor(to.dataset.takeover);if(r==='ok'){toast('That door is yours now');S.selPin=null;await loadWorkspaceData()}else if(r==='protected')toast('Still inside the protection window');}catch(err){toast(err.message)}return}
  const mz=t.closest('[data-mz="colorby"]');if(mz){stop();S.colorBy=S.colorBy==='rep'?'status':'rep';render();return}
  if(t.closest('[data-act="exportmsgs"]')){stop();try{const rows=await S.api.exportMessages(S.ws.id);save(`messages-${todayKey()}.json`,JSON.stringify(rows,null,1))}catch(err){toast(err.message)}return}
  if(t.closest('[data-act="exportteam"]')){stop();exportCSV();return}
  if(t.closest('[data-act="releaselead"]')){stop();const l=S.leads.get(S.open);if(!l)return;if(!(await confirmBox('Give this lead back to the board? Another rep can claim it.','Give back')))return;
    try{await S.api.releaseLead(l.id,'');S.leads.delete(l.id);persist();closeLead();toast('Back on the board');refreshBoard()}catch(err){toast(err.message)}return}
  if(t.closest('[data-act="settings"]')){stop();settingsModal();return}
  if(t.closest('[data-act="knock"]')&&S.role==='office'){stop();postLeadModal();return}
},true);

document.addEventListener('change',async e=>{const t=e.target;
  if(t.dataset.assignpool!==undefined&&t.value){try{await S.api.assignLead(t.dataset.assignpool,t.value);toast('Assigned to '+mfirst(t.value));await loadWorkspaceData()}catch(err){toast(err.message)}return}
  if(t.dataset.assign!==undefined){const v=t.value;try{await S.api.assignLead(t.dataset.assign,v==='__board'?null:(v||null));toast(v==='__board'?'Sent back to the board':'Now worked by '+mfirst(v));await loadWorkspaceData()}catch(err){toast(err.message)}return}
  if(t.dataset.memrole!==undefined){try{await S.api.updateMember(S.ws.id,t.dataset.memrole,{role:t.value});S.members.get(t.dataset.memrole).role=t.value;toast('Role updated')}catch(err){toast(err.message)}return}
  if(t.id==='chat-photo'&&t.files[0]){sendChat(t.files[0]);t.value='';return}
});
document.addEventListener('keydown',e=>{if(e.key==='Enter'){if(e.target.id==='chat-in'){e.preventDefault();sendChat()}
  if(e.target.id==='au-email')$('[data-auth="send"]')?.click();if(e.target.id==='au-code')$('[data-auth="verify"]')?.click();if(e.target.id==='shout')$('[data-act="shout"]')?.click()}});

const ZONE_REASONS=['New roofs','Recently replaced','HOA / no soliciting','Not our market','Other'];
function zones(){return S.zones||(S.zones=[])}
const canEditZone=z=>z&&(z.created_by===S.me||isMgr());
function inPoly(pt,poly){let c=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++){const [yi,xi]=poly[i],[yj,xj]=poly[j];
  if(((yi>pt.lat)!==(yj>pt.lat))&&(pt.lng<(xj-xi)*(pt.lat-yi)/(yj-yi)+xi))c=!c}return c}
function zoneAt(ll){return zones().find(z=>z.points.length>2&&inPoly(ll,z.points))}
function addSkipPoint(ll){S.zoneDraft=S.zoneDraft||{points:[]};S.zoneDraft.points.push([+ll.lat.toFixed(6),+ll.lng.toFixed(6)]);render()}
function drawZones(){if(!MV.map)return;if(MV.zoneLayer){MV.map.removeLayer(MV.zoneLayer);MV.zoneLayer=null}
  MV.zoneLayer=L.layerGroup().addTo(MV.map);
  for(const z of zones()){if(z.points.length<3)continue;const on=S.selZone===z.id;
    const pg=L.polygon(z.points,{color:'#E5372B',weight:on?3:2,dashArray:'6 6',fillColor:'#E5372B',fillOpacity:on?.28:.16,interactive:(S.mapMode||'browse')==='browse'}).addTo(MV.zoneLayer);
    pg.bindTooltip('⛔ '+z.name,{permanent:true,direction:'center',className:'zone-tip'});
    pg.on('click',ev=>{L.DomEvent.stopPropagation(ev);S.selPin=null;S.selZone=z.id;render()})}
  const d=S.zoneDraft;if(d&&d.points.length){(d.points.length>2?L.polygon(d.points,{color:'#E5372B',weight:3,fillOpacity:.15,interactive:false}):L.polyline(d.points,{color:'#E5372B',weight:3,interactive:false})).addTo(MV.zoneLayer);
    d.points.forEach(x=>L.circleMarker(x,{radius:6,color:'#fff',weight:2,fillColor:'#E5372B',fillOpacity:1,interactive:false}).addTo(MV.zoneLayer))}}
function skipCard(){const n=S.zoneDraft?S.zoneDraft.points.length:0;
  return `<div class="map-pop card"><b>Mark a skip zone</b><span class="muted" style="font-size:13px">Tap around the edge of a neighborhood or street that doesn’t need roofs. ${n?n+' point'+(n>1?'s':'')+' so far.':''}</span>
    <div class="btns"><button class="btn" data-zone="undo" ${n?'':'disabled'}>Undo</button><button class="btn" data-zone="cancel">Cancel</button><button class="btn pri grow" data-zone="done" ${n>2?'':'disabled'}>Done</button></div>
    ${zones().length?`<span class="muted" style="font-size:12.5px">${zones().length} skip zone${zones().length>1?'s':''} on your map. Switch to Browse and tap one to edit it.</span>`:''}</div>`}
function zoneCard(){const z=zones().find(x=>x.id===S.selZone);if(!z)return'';
  return `<div class="map-pop card"><div class="row"><span class="grow"><b style="display:block">⛔ ${esc(z.name)}</b><span class="muted" style="font-size:13px">${esc(z.reason||'')}${z.reason?' · ':''}marked by ${esc(mname(z.created_by))} · ${esc(fmtDate(z.created_at||Date.now()))}</span></span><button class="iconbtn" data-zone="close" aria-label="Close">✕</button></div>
    ${z.note?`<div style="font-size:14px">${esc(z.note)}</div>`:''}${canEditZone(z)?`<div class="btns"><button class="btn" data-zone="edit">Edit</button><button class="btn dng" data-zone="delete">Delete zone</button></div>`:`<span class="muted" style="font-size:12.5px">Only ${esc(mfirst(z.created_by))} or a manager can change this zone.</span>`}</div>`}
function zoneModal(z){const isNew=!z.id;
  const m=modal(`<div class="row"><h2 class="grow">${isNew?'Name this skip zone':'Edit skip zone'}</h2><button class="iconbtn" data-c="x" aria-label="Close">✕</button></div>
    <label class="field"><span>Name</span><input type="text" id="z-name" value="${esc(z.name||'')}" placeholder="Brookstone subdivision"></label>
    <div class="chips" id="z-reasons">${ZONE_REASONS.map(r=>`<button class="chip plain" data-r="${esc(r)}" aria-pressed="${(z.reason||'New roofs')===r}">${esc(r)}</button>`).join('')}</div>
    <label class="field"><span>Note (optional)</span><textarea id="z-note" placeholder="Whole street re-roofed after the 2025 hail storm">${esc(z.note||'')}</textarea></label>
    <button class="btn pri" data-c="save">Save skip zone</button>`);
  let reason=z.reason||'New roofs';setTimeout(()=>$('#z-name',m)?.focus(),60);
  m.addEventListener('click',e=>{const r=e.target.closest('[data-r]');if(r){reason=r.dataset.r;$$('#z-reasons .chip',m).forEach(b=>b.setAttribute('aria-pressed',b===r));return}
    const c=e.target.closest('[data-c]');if(!c)return;if(c.dataset.c==='x'){m.remove();if(isNew)render();return}
    const name=$('#z-name',m).value.trim()||reason;const note=$('#z-note',m).value.trim();
    c.disabled=true;S.api.saveSkipZone(S.ws.id,isNew?{name,reason,note,points:z.points}:{...z,name,reason,note}).then(async()=>{S.zones=await S.api.skipZones(S.ws.id);
      m.remove();S.zoneDraft=null;S.mapMode='browse';render();toast(isNew?(isCompany()?'Skip zone saved — your whole team sees it':'Skip zone saved'):'Updated')}).catch(err=>{c.disabled=false;toast(err.message||'Couldn’t save the zone')})})}
document.addEventListener('click',async e=>{const b=e.target.closest('[data-zone]');if(!b)return;e.stopImmediatePropagation();const k=b.dataset.zone;
  if(k==='undo'&&S.zoneDraft){S.zoneDraft.points.pop();render()}
  if(k==='cancel'){S.zoneDraft=null;S.mapMode='browse';render()}
  if(k==='done'&&S.zoneDraft&&S.zoneDraft.points.length>2)zoneModal({points:S.zoneDraft.points});
  if(k==='close'){S.selZone=null;render()}
  const z=zones().find(x=>x.id===S.selZone);
  if(k==='edit'&&z&&canEditZone(z))zoneModal(z);
  if(k==='edit'&&z&&!canEditZone(z))toast('Only the person who drew it or a manager can change it');
  if(k==='delete'&&z&&canEditZone(z)){if(!(await confirmBox(`Delete the skip zone “${z.name}”?`)))return;try{await S.api.deleteSkipZone(z.id);S.zones=await S.api.skipZones(S.ws.id);S.selZone=null;render();toast('Skip zone deleted')}catch(err){toast(err.message)}}
},true);
/* ---------- tools + storm tracker ---------- */
// Storm reports: NWS Local Storm Reports via the Iowa Environmental Mesonet (free, CORS-open).
// Live warnings: api.weather.gov active alerts for a point.
const LSR_URL='https://mesonet.agron.iastate.edu/geojson/lsr.geojson';
const ST={cache:new Map(),rows:[],busy:false,err:'',key:'',alerts:[],alertsAt:0,alertsBusy:false,sel:null,moveT:0,capped:false,tooWide:false};
const ST_RANGES={'1d':['24 hrs',1],'7d':['7 days',7],'30d':['30 days',30],'1y':['1 year',365],'3y':['3 years',1095]};
const HAIL_SIZES=[[.25,'Pea'],[.5,'Marble'],[.75,'Penny'],[.88,'Nickel'],[1,'Quarter'],[1.25,'Half dollar'],[1.5,'Ping pong ball'],[1.75,'Golf ball'],[2,'Hen egg'],[2.5,'Tennis ball'],[2.75,'Baseball'],[3,'Tea cup'],[4,'Softball'],[4.5,'Grapefruit']];
const hailName=m=>{let n='';for(const [s,x] of HAIL_SIZES)if(m>=s-.01)n=x;return n};
const fmtIn=m=>(Math.round(m*100)/100).toString().replace(/^0\./,'.')+'"';
function sFilt(){return Object.assign({range:'30d',min:0,hail:true,wind:true,tor:true,day:'',look:'swath'},S.settings.stormF||{})}
function setSFilt(p){S.settings.stormF=Object.assign(sFilt(),p);saveSettings()}
const stormOn=()=>S.tab==='storms'||(S.tab==='map'&&!!S.settings.stormLayer);
function lsrKind(p){const tt=String(p.typetext||'').toUpperCase(),t=p.type;
  if(t==='H'||tt.includes('HAIL'))return tt.includes('MARINE')?null:'hail';
  if(t==='T'||tt==='TORNADO')return 'tor';
  if(tt.includes('MARINE'))return null;
  if(tt.includes('WND')||tt.includes('WIND')||['G','D','O','N'].includes(t))return 'wind';
  return null}
function normLSR(f){const p=f.properties||{};const kind=lsrKind(p);if(!kind)return null;
  const c=f.geometry&&f.geometry.coordinates;const lat=+(p.lat??(c&&c[1])),lng=+(p.lon??(c&&c[0]));if(!isFinite(lat)||!isFinite(lng))return null;
  const t=Date.parse(p.valid);if(!isFinite(t))return null;const mag=parseFloat(p.magnitude)||0;
  return{id:[p.valid,lat.toFixed(4),lng.toFixed(4),p.type].join('|'),kind,mag,t,lat,lng,
    tt:String(p.typetext||''),city:String(p.city||''),county:String(p.county||''),st:String(p.st||p.state||''),src:String(p.source||''),remark:String(p.remark||'').slice(0,400),q:p.qualifier||''}}
async function stormFetch(b,days,snap=true){
  const g=snap?.5:.01,r=x=>Math.round(x*1000)/1000;
  const w=r(Math.floor(b.w/g)*g),e=r(Math.ceil(b.e/g)*g),s=r(Math.floor(b.s/g)*g),n=r(Math.ceil(b.n/g)*g);
  const key=[w,e,s,n,days].join(',');const c=ST.cache.get(key);if(c&&Date.now()-c.at<10*60e3)return c;
  const iso=d=>d.toISOString().slice(0,16)+'Z';const ets=new Date(Date.now()+36e5),sts=new Date(Date.now()-days*864e5);
  const url=`${LSR_URL}?west=${w}&east=${e}&south=${s}&north=${n}&sts=${iso(sts)}&ets=${iso(ets)}`;
  const ac=new AbortController();const to=setTimeout(()=>ac.abort(),20000);
  try{const res=await fetch(url,{signal:ac.signal});if(!res.ok)throw new Error('HTTP '+res.status);const j=await res.json();
    const feats=j.features||[];const seen=new Set(),rows=[];
    for(const f of feats){const x=normLSR(f);if(x&&!seen.has(x.id)){seen.add(x.id);rows.push(x)}}
    rows.sort((a,b)=>b.t-a.t);const out={at:Date.now(),rows,capped:feats.length>=10000,key};ST.cache.set(key,out);
    if(ST.cache.size>40)ST.cache.delete(ST.cache.keys().next().value);return out}
  finally{clearTimeout(to)}}
function stormVisible(rows){const f=sFilt(),since=Date.now()-ST_RANGES[f.range][1]*864e5;return rows.filter(x=>x.t>=since&&(x.kind==='hail'?f.hail&&x.mag>=f.min:x.kind==='wind'?f.wind:f.tor)&&(!f.day||dayKey(x.t)===f.day))}
async function stormLoad(){if(!MV.map||!stormOn())return;const bd=MV.map.getBounds();
  const b={w:bd.getWest(),e:bd.getEast(),s:bd.getSouth(),n:bd.getNorth()};const days=ST_RANGES[sFilt().range][1];
  ST.tooWide=(b.e-b.w)*(b.n-b.s)>(days>400?6:20);if(ST.tooWide){ST.rows=[];drawStorms();paintStormInfo();return}
  ST.busy=true;ST.err='';paintStormInfo();
  try{const out=await stormFetch(b,days);ST.rows=out.rows;ST.capped=out.capped;ST.key=out.key}
  catch(e){ST.err=navigator.onLine===false?'You’re offline — storm reports need a connection.':'Couldn’t reach the storm report service. Try again in a minute.'}
  ST.busy=false;drawStorms();paintStormInfo()}
function stormColor(x){if(x.kind==='tor')return '#E11D48';if(x.kind==='wind')return '#8B5CF6';return x.mag>=2?'#B91C1C':x.mag>=1.75?'#EF4444':x.mag>=1?'#F59E0B':'#38BDF8'}
// Hail swath look: each hail report becomes a soft footprint (~3 mi), and reports from the same storm
// moving across the map are joined into a track. Size is encoded as gray, combined with "lighten" (max),
// then colored with a radar-style hail palette. Drawn from reports — not radar.
const SW_STOPS=[[.5,[110,231,183]],[.75,[52,211,153]],[1,[250,204,21]],[1.5,[251,146,60]],[1.75,[239,68,68]],[2,[220,38,38]],[2.5,[217,70,239]],[3,[147,51,234]],[3.5,[109,40,217]]];
const SW_MAX=3.5;
const SW_LUT=(()=>{const lut=new Uint8ClampedArray(256*4);for(let g=0;g<256;g++){const s=g/255*SW_MAX;let c=SW_STOPS[0][1];
  for(let i=0;i<SW_STOPS.length-1;i++){const [a,ca]=SW_STOPS[i],[b,cb]=SW_STOPS[i+1];if(s>=a&&s<=b){const t=(s-a)/(b-a);c=ca.map((v,k)=>v+(cb[k]-v)*t);break}if(s>b)c=cb}
  const al=s<.42?0:s<.62?(s-.42)/.2:1;lut.set([c[0],c[1],c[2],Math.round(al*170)],g*4)}return lut})();
const SwathLayer=window.L?L.Layer.extend({
  onAdd(map){this._map=map;map.on('moveend',this._redraw,this);this._redraw()},
  onRemove(map){map.off('moveend',this._redraw,this);if(this._ov){map.removeLayer(this._ov);this._ov=null}if(this._url){URL.revokeObjectURL(this._url);this._url=null}},
  setRows(rows){this._rows=rows||[];if(this._map)this._redraw()},
  _redraw(){const map=this._map;if(!map)return;const rows=this._rows||[];const tok=this._tok=(this._tok||0)+1;
    if(!rows.length){if(this._ov){map.removeLayer(this._ov);this._ov=null}return}
    const sz=map.getSize(),pad=Math.round(Math.max(sz.x,sz.y)*.35),sc=.5;
    const W=Math.max(1,Math.round((sz.x+pad*2)*sc)),H=Math.max(1,Math.round((sz.y+pad*2)*sc));
    const cv=document.createElement('canvas');cv.width=W;cv.height=H;const g=cv.getContext('2d');
    g.fillStyle='#000';g.fillRect(0,0,W,H);g.globalCompositeOperation='lighten';g.lineCap='round';g.lineJoin='round';
    const c=map.getCenter(),mpp=40075016.686*Math.cos(c.lat*Math.PI/180)/Math.pow(2,map.getZoom()+8);
    const R=Math.max(2.2,2000/mpp*sc);// core half-width ≈ 1.5 mi, soft edge to ≈ 3 mi
    const pt=x=>{const p=map.latLngToContainerPoint([x.lat,x.lng]);return [(p.x+pad)*sc,(p.y+pad)*sc]};
    const gray=v=>{const n=Math.round(Math.min(1,v/SW_MAX)*255);return `rgb(${n},${n},${n})`};
    const RINGS=[[2,.5],[1.55,.72],[1.1,.88],[.65,1]];
    const hail=rows.filter(x=>x.kind==='hail'&&x.mag>0).sort((a,b)=>a.t-b.t);
    // join reports from the same storm: same day, within ~20 mi and 75 min of an earlier report
    for(let i=0;i<hail.length;i++){const b=hail[i];let best=null,bd=1e9;
      for(let j=i-1;j>=0;j--){const a=hail[j];if(b.t-a.t>75*60e3)break;const d=hav(a,b);if(d<20&&d<bd){bd=d;best=a}}
      if(best){const [x1,y1]=pt(best),[x2,y2]=pt(b);const v=Math.min(best.mag,b.mag)*.92;
        for(const [w,f] of RINGS){g.strokeStyle=gray(v*f);g.lineWidth=R*2*w;g.beginPath();g.moveTo(x1,y1);g.lineTo(x2,y2);g.stroke()}}}
    for(const x of hail){const [px,py]=pt(x);for(const [w,f] of RINGS){g.fillStyle=gray(x.mag*f);g.beginPath();g.arc(px,py,R*w,0,Math.PI*2);g.fill()}}
    const img=g.getImageData(0,0,W,H),d=img.data;
    for(let i=0;i<d.length;i+=4){const k=d[i]*4;d[i]=SW_LUT[k];d[i+1]=SW_LUT[k+1];d[i+2]=SW_LUT[k+2];d[i+3]=SW_LUT[k+3]}
    g.globalCompositeOperation='source-over';g.putImageData(img,0,0);
    const nw=map.containerPointToLatLng([-pad,-pad]),se=map.containerPointToLatLng([sz.x+pad,sz.y+pad]);
    cv.toBlob(bl=>{if(tok!==this._tok||!this._map||!bl)return;const url=URL.createObjectURL(bl);
      const old=this._ov,oldUrl=this._url;this._url=url;
      const z=map.getZoom();this._ov=L.imageOverlay(url,[nw,se],{interactive:false,className:'swath-img',pane:'overlayPane',opacity:z<=11?1:z<=13?.8:z<=15?.5:.32}).addTo(map);
      if(old)setTimeout(()=>{map.removeLayer(old);if(oldUrl)URL.revokeObjectURL(oldUrl)},60)},'image/png')}}):null;
function drawStorms(){if(!MV.map)return;if(!MV.stormLayer){MV.stormRend=L.canvas({padding:.3});MV.swath=new SwathLayer();MV.swath.addTo(MV.map);MV.stormLayer=L.layerGroup().addTo(MV.map);MV.alertLayer=L.layerGroup().addTo(MV.map)}
  MV.stormLayer.clearLayers();MV.alertLayer.clearLayers();if(!stormOn()){MV.swath.setRows([]);return}
  for(const a of ST.alerts)if(a.geom&&/Warning/.test(a.event)){try{L.geoJSON(a.geom,{interactive:false,style:{color:a.event.startsWith('Tornado')?'#E11D48':'#F59E0B',weight:2.5,dashArray:'6 5',fillOpacity:.08}}).addTo(MV.alertLayer)}catch(e){}}
  const swath=sFilt().look!=='dots';const vis=stormVisible(ST.rows).slice().sort((a,b)=>a.mag-b.mag);
  MV.swath.setRows(swath?vis:[]);
  for(const x of vis){const sel=ST.sel===x.id;let rad=x.kind==='hail'?Math.min(17,5+x.mag*5):x.kind==='tor'?9:6;if(swath)rad=x.kind==='hail'?4:5;
    L.circleMarker([x.lat,x.lng],{renderer:MV.stormRend,radius:sel?rad+4:rad,color:sel?'#fff':swath&&x.kind==='hail'?'rgba(255,255,255,.95)':'rgba(0,0,0,.55)',weight:sel?3:swath?1.5:1.2,fillColor:swath&&x.kind==='hail'?'rgba(15,20,30,.85)':stormColor(x),fillOpacity:.9,bubblingMouseEvents:false})
      .on('click',ev=>{L.DomEvent.stopPropagation(ev);ST.sel=x.id;S.selPin=null;render()}).addTo(MV.stormLayer)}}
function stormLegend(){const sw=sFilt().look!=='dots';
  return `<div class="st-legend"><div class="st-look" role="tablist" aria-label="Storm map style"><button role="tab" data-slook="swath" aria-selected="${sw}">Swath</button><button role="tab" data-slook="dots" aria-selected="${!sw}">Dots</button></div>
    ${sw?`<div class="sw-scale"><span class="sw-bar"></span><span class="sw-lab"><b>¾"</b><b>1"</b><b>1½"</b><b>2"</b><b>2½"</b><b>3"+</b></span></div>`
      :`<div class="st-keys"><span><i style="--c:#38BDF8"></i>&lt;1"</span><span><i style="--c:#F59E0B"></i>1"</span><span><i style="--c:#EF4444"></i>1¾"</span><span><i style="--c:#B91C1C"></i>2"+</span><span><i style="--c:#8B5CF6"></i>Wind</span></div>`}</div>`}
function paintStormInfo(){const el=$('#st-info');if(el)el.innerHTML=stormInfoHTML();const li=$('#st-list');if(li)li.innerHTML=stormListHTML();const ld=$('#st-load');if(ld)ld.hidden=!ST.busy}
function stormInfoHTML(){if(ST.tooWide)return `<div class="banner">Zoom in to load storm reports for this area.</div>`;
  if(ST.err)return `<div class="banner st-err row"><span class="grow">${esc(ST.err)}</span><button class="btn sm" data-sx="retry">Retry</button></div>`;
  if(ST.capped)return `<div class="banner">Showing the first 10,000 reports — zoom in for the full picture.</div>`;return ''}
function inView(x){if(!MV.map)return true;return MV.map.getBounds().contains([x.lat,x.lng])}
function stormListHTML(){if(ST.busy&&!ST.rows.length)return `<div class="card empty"><strong>Loading storm reports…</strong>Pulling National Weather Service reports for this area.</div>`;
  const vis=stormVisible(ST.rows).filter(inView);const f=sFilt();
  if(!vis.length)return ST.tooWide||ST.err?'':`<div class="card empty"><strong>No reports here</strong>No ${f.hail&&!f.wind&&!f.tor?'hail':'hail or wind'} reports in the last ${ST_RANGES[f.range][0]}${f.min?` at ${fmtIn(f.min)} or bigger`:''}. Try a longer time range or zoom out.</div>`;
  const days=new Map();for(const x of vis){const k=dayKey(x.t);if(!days.has(k))days.set(k,[]);days.get(k).push(x)}
  let h=`<div class="sec-h"><h2>${f.day?'One storm day':'Storm days'}</h2><span class="muted">${vis.length} report${vis.length>1?'s':''} on the map${f.day?` · <button class="linkbtn" data-sday="">Show all days</button>`:''}</span></div>`;
  let n=0;for(const [k,xs] of days){if(n++>=40)break;const hail=xs.filter(x=>x.kind==='hail'),maxH=hail.reduce((a,x)=>Math.max(a,x.mag),0),wind=xs.filter(x=>x.kind==='wind'),tor=xs.filter(x=>x.kind==='tor');
    const d=new Date(xs[0].t);
    h+=`<section class="card st-day"><button class="st-dayh" data-sday="${f.day===k?'':k}"><div class="st-date"><b>${d.toLocaleDateString([], {day:'numeric'})}</b><span>${d.toLocaleDateString([], {month:'short'})}</span></div>
      <div class="grow"><div class="t1">${d.toLocaleDateString([], {weekday:'long'})}${d.getFullYear()!==new Date().getFullYear()?' · '+d.getFullYear():''}</div>
      <div class="st-tags">${hail.length?`<span class="st-tag" style="--c:${stormColor({kind:'hail',mag:maxH})}">${hail.length} hail · up to ${fmtIn(maxH)}</span>`:''}${wind.length?`<span class="st-tag" style="--c:#8B5CF6">${wind.length} wind</span>`:''}${tor.length?`<span class="st-tag" style="--c:#E11D48">${tor.length} tornado</span>`:''}</div></div>
      <span class="muted st-chev">${f.day===k?'All':'Map ›'}</span></button>
      <div class="list">${xs.slice(0,f.day?200:6).map(x=>stormRow(x)).join('')}${!f.day&&xs.length>6?`<button class="li st-more" data-sday="${k}">+ ${xs.length-6} more on this day</button>`:''}</div></section>`}
  return h}
function stormRow(x){return `<button class="li st-row${ST.sel===x.id?' on':''}" data-sr="${esc(x.id)}"><span class="st-dot" style="--c:${stormColor(x)};--s:${x.kind==='hail'?Math.min(26,10+x.mag*7):12}px"></span>
  <span class="grow"><span class="t1">${stormTitle(x)}</span><span class="t2 trunc" style="display:block">${esc(stormPlace(x))} · ${new Date(x.t).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'})}</span></span></button>`}
const stormTitle=x=>x.kind==='hail'?`${fmtIn(x.mag)} hail${hailName(x.mag)?` <span class="muted" style="font-weight:600">· ${esc(hailName(x.mag))}</span>`:''}`:x.kind==='tor'?'Tornado':(x.mag?`${Math.round(x.mag)} mph wind`:'Wind damage');
const stormPlace=x=>[x.city&&x.city.replace(/\b(\w)(\w*)/g,(m,a,b)=>a+b.toLowerCase()),x.st].filter(Boolean).join(', ')||'Location reported';
function stormCard(){const x=ST.rows.find(r=>r.id===ST.sel);if(!x)return'';const d=new Date(x.t);
  return `<div class="map-pop card st-pop"><div class="row" style="align-items:flex-start"><span class="st-dot" style="--c:${stormColor(x)};--s:${x.kind==='hail'?Math.min(30,12+x.mag*8):14}px;margin-top:2px"></span>
    <div class="grow"><div style="font-weight:800;font-size:17px;letter-spacing:-.01em">${stormTitle(x)}</div>
    <div class="muted" style="font-size:13px">${d.toLocaleDateString([], {weekday:'short',month:'short',day:'numeric',year:'numeric'})} · ${d.toLocaleTimeString([], {hour:'numeric',minute:'2-digit'})} · ${esc(stormPlace(x))}</div></div>
    <button class="iconbtn" data-sx="unsel" aria-label="Close">✕</button></div>
    ${x.remark?`<p class="st-remark">${esc(x.remark)}</p>`:''}
    <div class="muted" style="font-size:12px">Reported by ${esc(x.src?x.src.toLowerCase():'unknown source')} · NWS storm report${x.q==='E'?' · estimated':x.q==='M'?' · measured':''}</div>
    <div class="btns">${S.tab==='storms'?`<button class="btn pri grow" data-sx="canvass">Canvass here</button>`:''}<button class="btn${S.tab==='storms'?'':' grow'}" data-sday="${dayKey(x.t)}">Just this storm day</button></div></div>`}
function stormChips(){const f=sFilt();
  return `<div class="chips hscroll" role="group" aria-label="Time range">${Object.entries(ST_RANGES).map(([k,[lab]])=>`<button class="chip plain" data-sfr="${k}" aria-pressed="${f.range===k}">${lab}</button>`).join('')}</div>
  <div class="chips hscroll" role="group" aria-label="Report types">
    <button class="chip" style="--c:#F59E0B" data-skind="hail" aria-pressed="${f.hail}"><span class="sw"></span>Hail</button>
    <button class="chip" style="--c:#8B5CF6" data-skind="wind" aria-pressed="${f.wind}"><span class="sw"></span>Wind</button>
    <button class="chip" style="--c:#E11D48" data-skind="tor" aria-pressed="${f.tor}"><span class="sw"></span>Tornado</button>
    <span class="st-sep"></span>
    ${[[0,'Any size'],[1,'1"+'],[1.75,'1¾"+']].map(([v,l])=>`<button class="chip plain" data-smin="${v}" aria-pressed="${f.min===v}">${l}</button>`).join('')}</div>`}
function alertsHTML(compact){const a=ST.alerts;if(!a.length)return'';
  return a.slice(0,compact?2:5).map(x=>{const warn=/Warning/.test(x.event);const tor=x.event.startsWith('Tornado');
    return `<${compact?'button data-tab="storms"':'div'} class="st-alert${warn?' warn':''}${tor?' tor':''}"><span class="st-alert-i" aria-hidden="true">${tor?'🌪':'⛈'}</span><span class="grow"><b>${esc(x.event)}</b><span>${[x.hail?`hail up to ${fmtIn(x.hail)}`:'',x.wind?`wind ${esc(x.wind)}`:'',x.ends?'until '+new Date(x.ends).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'}):''].filter(Boolean).join(' · ')||esc(x.area||'')}</span></span>${compact?'<span class="muted">›</span>':''}</${compact?'button':'div'}>`}).join('')}
async function loadAlerts(force){if(ST.alertsBusy)return false;if(!force&&ST.alertsAt&&Date.now()-ST.alertsAt<5*60e3)return false;
  const v=MV.gps.pos||lsGet('ridgeline.mapview',null)||{lat:MAP_HOME[0],lng:MAP_HOME[1]};ST.alertsBusy=true;
  try{const ac=new AbortController();const to=setTimeout(()=>ac.abort(),12000);
    const r=await fetch(`https://api.weather.gov/alerts/active?point=${(+v.lat).toFixed(4)},${(+v.lng).toFixed(4)}`,{signal:ac.signal,headers:{Accept:'application/geo+json'}});clearTimeout(to);
    if(!r.ok)throw 0;const j=await r.json();const keep=['Tornado Warning','Severe Thunderstorm Warning','Tornado Watch','Severe Thunderstorm Watch'];
    const before=ST.alerts.map(x=>x.id).join();
    ST.alerts=(j.features||[]).filter(f=>keep.includes(f.properties&&f.properties.event)).map(f=>{const p=f.properties,pr=p.parameters||{};
      return{id:p.id||f.id,event:p.event,area:p.areaDesc||'',ends:p.ends||p.expires,hail:parseFloat((pr.maxHailSize||[])[0])||0,wind:(pr.maxWindGust||[])[0]||'',geom:f.geometry}})
      .sort((a,b)=>(/Warning/.test(b.event)-/Warning/.test(a.event)));
    ST.alertsAt=Date.now();return ST.alerts.map(x=>x.id).join()!==before}
  catch(e){return false}finally{ST.alertsBusy=false}}
function vStorms(){if(['pin','skip'].includes(S.mapMode))S.mapMode='browse';const f=sFilt();
  return `<div class="stack"><div class="row"><button class="iconbtn back" data-tab="tools" aria-label="Back to tools"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg></button>
    <h2 class="grow" style="font-size:28px;letter-spacing:-.03em">Storms</h2><button class="btn sm" data-sx="alerts">↻ Warnings</button></div>
    ${alertsHTML(false)}
    ${stormChips()}
    <div class="mapwrap st-map" id="mapwrap"><div id="mapslot" class="mapslot"></div>
      <div class="map-zoom"><button data-mz="gps" aria-label="Show my location" class="${MV.gps.watch?'gps-on':''}"><svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M21 3 3 10.5l7.5 3L13.5 21z"/></svg></button><button data-mz="in" aria-label="Zoom in">+</button><button data-mz="out" aria-label="Zoom out">−</button><button data-mz="layer" aria-label="Change map style" style="font-size:10.5px;font-weight:800">${{hybrid:'HYB',sat:'SAT',street:'MAP'}[MV.base]||'HYB'}</button></div>
      ${stormLegend()}
      <div class="st-load" id="st-load"${ST.busy?'':' hidden'}><span class="spin"></span>Loading reports…</div>
      ${!window.L?`<div class="map-empty"><b>Map can’t load</b><span>Connect to the internet once so the map can download.</span></div>`:''}
      ${stormCard()}</div>
    <div id="st-info">${stormInfoHTML()}</div>
    <label class="st-toggle card"><span class="grow"><b>Show storms on the Knock map</b><span class="muted">Same filters, layered under your pins</span></span><input type="checkbox" role="switch" data-slayer ${S.settings.stormLayer?'checked':''}></label>
    <div id="st-list">${stormListHTML()}</div>
    <p class="muted" style="font-size:12px;margin:4px 4px 0">Reports come from the National Weather Service (storm spotters, police, the public), via the Iowa Environmental Mesonet. The swath view is drawn from those reports, not from radar — it shows where hail was reported and how storms tracked, and a street can still be hit with no report nearby. Last ${ST_RANGES[f.range][0].toLowerCase()} shown.</p></div>`}
/* lead storm history */
const bearing=(a,b)=>{const r=x=>x*Math.PI/180,y=Math.sin(r(b.lng-a.lng))*Math.cos(r(b.lat)),x=Math.cos(r(a.lat))*Math.sin(r(b.lat))-Math.sin(r(a.lat))*Math.cos(r(b.lat))*Math.cos(r(b.lng-a.lng));
  return ['N','NE','E','SE','S','SW','W','NW'][Math.round(((Math.atan2(y,x)*180/Math.PI)+360)%360/45)%8]};
async function leadStorms(l){if(!l.geo){toast('Looking up the address…');const g=await geocode(fullAddr(l));if(!g){toast('Pin this house on the map first, then try again');return}l.geo=g;saveLead(l)}
  const m=modal(`<h2>Storms near this house</h2><p class="muted" style="margin:0">Hail and wind reports within 10 miles, last 5 years.</p><div id="ls-body"><div class="empty"><span class="spin"></span> Loading…</div></div><div class="btns" style="justify-content:flex-end"><button class="btn" data-c="close">Done</button></div>`,'ls-modal');
  m.addEventListener('click',e=>{if(e.target.closest('[data-c="close"]'))m.remove()});
  const g=l.geo,dl=.16,dg=.16/Math.cos(g.lat*Math.PI/180);let rows;
  try{rows=(await stormFetch({w:g.lng-dg,e:g.lng+dg,s:g.lat-dl,n:g.lat+dl},5*365,false)).rows}
  catch(e){$('#ls-body',m).innerHTML=`<div class="banner st-err">Couldn’t reach the storm report service. Check your signal and try again.</div>`;return}
  const near=rows.map(x=>({...x,mi:hav(g,x)})).filter(x=>x.mi<=10&&(x.kind!=='hail'||x.mag>=.5)).sort((a,b)=>b.t-a.t);
  const have=new Set(l.storms.map(s=>s.date));
  const body=$('#ls-body',m);if(!body)return;
  if(!near.length){body.innerHTML=`<div class="empty"><strong>No reports nearby</strong>No hail or wind reports within 10 miles in the last 5 years. That doesn’t rule out damage — reports are only as good as who called them in.</div>`;return}
  const byDay=new Map();for(const x of near){const k=dayKey(x.t);if(!byDay.has(k))byDay.set(k,[]);byDay.get(k).push(x)}
  body.innerHTML=`<div class="list card ls-list">${[...byDay].map(([k,xs])=>{const best=xs.slice().sort((a,b)=>(b.kind==='hail')-(a.kind==='hail')||b.mag-a.mag)[0];const close=xs.reduce((a,x)=>Math.min(a,x.mi),99);
    const d=new Date(best.t);return `<div class="li" style="cursor:default"><span class="st-dot" style="--c:${stormColor(best)};--s:${best.kind==='hail'?Math.min(24,10+best.mag*6):12}px"></span>
      <span class="grow"><span class="t1">${d.toLocaleDateString([], {month:'short',day:'numeric',year:'numeric'})} · ${stormTitle(best)}</span><span class="t2" style="display:block">${xs.length>1?xs.length+' reports · ':''}closest ${close.toFixed(1)} mi ${bearing(g,xs.find(x=>x.mi===close))} · ${esc(stormPlace(best))}</span></span>
      ${have.has(k)?`<span class="pill" style="--c:var(--ok)">Added</span>`:`<button class="btn sm" data-lsadd="${k}">Add</button>`}</div>`}).join('')}</div>`;
  body.addEventListener('click',e=>{const b=e.target.closest('[data-lsadd]');if(!b)return;const k=b.dataset.lsadd,xs=byDay.get(k);
    const hail=xs.filter(x=>x.kind==='hail').reduce((a,x)=>Math.max(a,x.mag),0),wind=xs.filter(x=>x.kind==='wind').reduce((a,x)=>Math.max(a,x.mag),0);
    const close=xs.reduce((a,x)=>x.mi<a.mi?x:a);
    const dmg=xs.some(x=>x.kind==='wind'&&!x.mag),tor=xs.some(x=>x.kind==='tor');
    const what=[dmg&&!wind?'Wind damage':'',tor?'Tornado':''].filter(Boolean).join(' + ');
    l.storms.push({date:k,hail:hail?String(Math.round(hail*100)/100):'',wind:wind?String(Math.round(wind)):'',src:`${what?what+' · ':''}NWS report ${close.mi.toFixed(1)} mi ${bearing(g,close)}${close.city?' ('+stormPlace(close)+')':''}`,verified:false});
    l.log.push({t:Date.now(),text:`Storm added from NWS reports: ${k}`,by:S.me});saveLead(l);b.outerHTML=`<span class="pill" style="--c:var(--ok)">Added</span>`;renderSheet();toast('Storm added — marked “reported in area”')})}
/* tools page */
const TOOL_IC={
  storms:'<path d="M7 16a5 5 0 1 1 1.2-9.9A6 6 0 0 1 19.5 9 4 4 0 0 1 18 16.9"/><path d="m13 12-3 5h4l-3 5"/>',
  pitch:'<path d="M3 20h18"/><path d="M3 20 17 6"/><path d="M10 20a7 7 0 0 0-2.1-5"/>',
  calc:'<rect x="5" y="3" width="14" height="18" rx="2.5"/><path d="M8.5 7h7M8.5 11h.01M12 11h.01M15.5 11h.01M8.5 14.5h.01M12 14.5h.01M15.5 14.5h.01M8.5 18h.01M12 18h.01M15.5 18h.01"/>',
  table:'<rect x="3" y="4" width="18" height="16" rx="2.5"/><path d="M3 9.5h18M3 15h18M9.5 4v16"/>',
  hail:'<circle cx="8" cy="9" r="3.2"/><circle cx="16.5" cy="7.5" r="2"/><circle cx="14.5" cy="16" r="4.2"/><circle cx="6" cy="17.5" r="1.6"/>',
  comm:'<path d="M12 2v20M17 6.5C17 4.6 14.8 4 12 4S7 5 7 7.5 9.5 10.5 12 11s5 1.4 5 4-2.2 3.5-5 3.5S7 17.6 7 15.5"/>'};
const toolIc=(k,s=22)=>`<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${TOOL_IC[k]}</svg>`;
const TOOLS=[['storms','Storm tracker','Hail & wind reports, live warnings','#2F6BFF'],['pitch','Pitch gauge','Measure with your phone','#F2541B'],['calc','Roof calculator','Squares, waste & bundles','#12A150'],
  ['table','Pitch table','Degrees & multipliers','#8B5CF6'],['hail','Hail sizes','Coin & ball reference','#0EA5B7'],['comm','Commission','What a job pays you','#E58A00']];
function vTools(){const live=ST.alerts.length;
  return `<div class="stack"><div class="row"><h2 class="grow" style="font-size:28px;letter-spacing:-.03em">Tools</h2></div>
  ${alertsHTML(true)}
  <div class="tools-grid">${TOOLS.map(([k,t,s,c])=>`<button class="card tool" data-tool="${k}" style="--c:${c}"><span class="tool-ic">${toolIc(k)}</span>${k==='storms'&&live?'<span class="tool-live">Live</span>':''}<b>${t}</b><span>${s}</span></button>`).join('')}</div></div>`}
function homeTools(){return `<section><div class="sec-h"><h2>Tools</h2><button class="linkbtn" data-tab="tools">All tools ›</button></div>
  ${alertsHTML(true)}
  <div class="tools-row">${TOOLS.slice(0,4).map(([k,t,s,c])=>`<button class="card tool sm" data-tool="${k}" style="--c:${c}"><span class="tool-ic">${toolIc(k,20)}</span><b>${t.replace(' tracker','').replace('Roof calculator','Calculator')}</b></button>`).join('')}</div></section>`}
function openTool(k){
  if(k==='storms'){location.hash='storms';return}
  if(k==='pitch'){openPitch(null);return}
  if(k==='calc'){const opts=Array.from({length:19},(_,i)=>`<option value="${i}"${i===6?' selected':''}>${i}/12</option>`).join('');
    const m=modal(`<h2>Roof calculator</h2>
      <div class="grid2"><label class="field"><span>Length (ft)</span><input id="tc-len" inputmode="decimal" placeholder="60"></label><label class="field"><span>Width (ft)</span><input id="tc-wid" inputmode="decimal" placeholder="40"></label></div>
      <label class="field"><span>…or footprint incl. overhangs (sq ft)</span><input id="tc-area" inputmode="decimal" placeholder="2,400"></label>
      <div class="grid2"><label class="field"><span>Pitch</span><select id="tc-pitch">${opts}</select></label><label class="field"><span>Waste</span><select id="tc-waste"><option value="10">10% · simple gable</option><option value="15" selected>15% · hip</option><option value="20">20% · cut-up</option></select></label></div>
      <div class="tc-out" id="tc-out"></div>
      <div class="btns" style="justify-content:flex-end"><button class="btn" data-c="close">Done</button></div>`);
    const calc=()=>{const area=num($('#tc-area',m).value)||num($('#tc-len',m).value)*num($('#tc-wid',m).value);const p=num($('#tc-pitch',m).value),w=num($('#tc-waste',m).value);
      const f=Math.sqrt(1+(p/12)**2),roof=area*f,sq=roof*(1+w/100)/100,sqR=Math.ceil(sq*3)/3;
      $('#tc-out',m).innerHTML=area?`<div class="tc-big"><b>${sqR.toFixed(sqR%1?1:0)}</b><span>squares to order</span></div>
        <div class="tc-grid"><div><span>Roof surface</span><b>${Math.round(roof).toLocaleString()} sq ft</b></div><div><span>Pitch multiplier</span><b>${f.toFixed(3)}</b></div>
        <div><span>Bundles (3 per sq)</span><b>${Math.ceil(sqR*3)}</b></div><div><span>Before waste</span><b>${(roof/100).toFixed(1)} sq</b></div></div>`
        :`<div class="muted" style="text-align:center;padding:10px">Enter length × width or the footprint.</div>`};
    m.addEventListener('input',calc);m.addEventListener('change',calc);m.addEventListener('click',e=>{if(e.target.closest('[data-c="close"]'))m.remove()});calc();return}
  if(k==='table'){const rows=Array.from({length:18},(_,i)=>i+1).map(p=>{const d=Math.atan(p/12)*180/Math.PI,f=Math.sqrt(1+(p/12)**2);
      return `<tr class="${p>=4&&p<=8?'hl':''}"><td><b>${p}/12</b></td><td>${d.toFixed(1)}°</td><td>${f.toFixed(3)}</td><td>${p<=7?'Walkable':p<=9?'Steep':'Very steep'}</td></tr>`}).join('');
    const m=modal(`<h2>Pitch table</h2><p class="muted" style="margin:0">Multiply the flat footprint by the multiplier to get roof surface.</p>
      <div class="pt-wrap"><table class="pt"><thead><tr><th>Pitch</th><th>Angle</th><th>Multiplier</th><th>Footing</th></tr></thead><tbody>${rows}</tbody></table></div>
      <div class="btns" style="justify-content:flex-end"><button class="btn" data-c="close">Done</button></div>`);
    m.addEventListener('click',e=>{if(e.target.closest('[data-c="close"]'))m.remove()});return}
  if(k==='hail'){const m=modal(`<h2>Hail sizes</h2><p class="muted" style="margin:0">The Weather Service calls hail <b>severe</b> at 1" (quarter) and up.</p>
      <div class="list card hs-list">${HAIL_SIZES.map(([s,n])=>`<div class="li" style="cursor:default"><span class="hs-ball"><i style="width:${Math.round(8+s*15)}px;height:${Math.round(8+s*15)}px;background:${stormColor({kind:'hail',mag:s})}"></i></span><span class="grow t1">${n}</span><b class="num">${fmtIn(s)}</b>${s>=1?'<span class="pill" style="--c:var(--danger)">Severe</span>':'<span class="pill hollow">—</span>'}</div>`).join('')}</div>
      <div class="btns" style="justify-content:flex-end"><button class="btn" data-c="close">Done</button></div>`);
    m.addEventListener('click',e=>{if(e.target.closest('[data-c="close"]'))m.remove()});return}
  if(k==='comm'){const m=modal(`<h2>Commission</h2>
      <label class="field"><span>Job total ($)</span><input id="cc-total" inputmode="decimal" placeholder="14,500"></label>
      <div class="grid2"><label class="field"><span>Job type</span><select id="cc-type"><option>Insurance</option><option>Retail</option><option>Repair</option></select></label>
      <label class="field"><span>Your rate (%)</span><input id="cc-rate" inputmode="decimal"></label></div>
      <div class="tc-out" id="cc-out"></div>
      <div class="btns" style="justify-content:flex-end"><button class="btn" data-c="close">Done</button></div>`);
    const rate=$('#cc-rate',m);rate.value=typeRate('Insurance')||'';
    const calc=e=>{if(e&&e.target&&e.target.id==='cc-type')rate.value=typeRate($('#cc-type',m).value)||'';const tot=num($('#cc-total',m).value),r=num(rate.value),c=tot*r/100;
      const goal=num(S.settings.goal),proj=moneyNow().proj;
      $('#cc-out',m).innerHTML=tot&&r?`<div class="tc-big"><b>${money(c)}</b><span>your commission</span></div>${goal?`<div class="muted" style="text-align:center;font-size:13.5px">Puts you at <b style="color:var(--ink)">${Math.round((proj+c)/goal*100)}%</b> of this month’s ${money(goal)} goal</div>`:''}`
        :`<div class="muted" style="text-align:center;padding:10px">Enter the job total${r?'':' and your rate'}.</div>`};
    m.addEventListener('input',calc);m.addEventListener('change',calc);m.addEventListener('click',e=>{if(e.target.closest('[data-c="close"]'))m.remove()});calc();return}}
document.addEventListener('click',async e=>{const t=e.target;
  const tl=t.closest('[data-tool]');if(tl){e.stopImmediatePropagation();openTool(tl.dataset.tool);return}
  const sfr=t.closest('[data-sfr]');if(sfr){setSFilt({range:sfr.dataset.sfr,day:''});ST.sel=null;render();return}
  const sk=t.closest('[data-skind]');if(sk){const f=sFilt();setSFilt({[sk.dataset.skind]:!f[sk.dataset.skind]});render();return}
  const slk=t.closest('[data-slook]');if(slk){e.stopImmediatePropagation();setSFilt({look:slk.dataset.slook});render();return}
  const smn=t.closest('[data-smin]');if(smn){setSFilt({min:+smn.dataset.smin});render();return}
  const sd=t.closest('[data-sday]');if(sd){e.stopImmediatePropagation();setSFilt({day:sd.dataset.sday});const d=sd.dataset.sday;
    if(d&&MV.map){const xs=stormVisible(ST.rows).filter(x=>dayKey(x.t)===d);if(xs.length)S.stormFit=xs.map(x=>[x.lat,x.lng])}render();if(S.tab==='storms')window.scrollTo({top:0,behavior:'smooth'});return}
  const sr=t.closest('[data-sr]');if(sr){const x=ST.rows.find(r=>r.id===sr.dataset.sr);if(x){ST.sel=x.id;S.flyTo=null;S.stormCenter={lat:x.lat,lng:x.lng};render();window.scrollTo({top:0,behavior:'smooth'})}return}
  const sx=t.closest('[data-sx]');if(sx){e.stopImmediatePropagation();const k=sx.dataset.sx;
    if(k==='retry'){ST.cache.clear();stormLoad()}
    if(k==='unsel'){ST.sel=null;render()}
    if(k==='alerts'){toast('Checking for warnings…');await loadAlerts(true);render();toast(ST.alerts.length?ST.alerts.length+' active alert'+(ST.alerts.length>1?'s':''):'No severe weather alerts here right now')}
    if(k==='canvass'){const x=ST.rows.find(r=>r.id===ST.sel);if(!x)return;ST.sel=null;S.settings.stormLayer=true;saveSettings();S.flyTo={lat:x.lat,lng:x.lng,z:16};S.mapMode='browse';location.hash='map'}
    if(k==='lead'){const l=S.leads.get(S.open);if(l)leadStorms(l)}
    return}},true);
document.addEventListener('change',e=>{const s=e.target.closest('[data-slayer]');if(!s)return;S.settings.stormLayer=s.checked;saveSettings();toast(s.checked?'Storms will show on your Knock map':'Storms hidden on the Knock map')});
setTimeout(()=>loadAlerts().then(ch=>{if(ch&&['home','tools','storms'].includes(S.tab)&&!$('.modal'))render()}),1500);
setInterval(()=>{if(document.visibilityState==='visible')loadAlerts().then(ch=>{if(ch&&['home','tools','storms'].includes(S.tab)&&!$('.modal'))render()})},5*60e3);
/* ---------- pitch gauge (phone sensors + camera) ---------- */
const PG={mode:'roof',deg:0,sign:1,locked:false,auto:false,stream:null,listening:false,got:false,orient:false,leadId:null,buf:[],est:null,lastT:0,prog:0,steady:false,shownP:null,shownD:null,raf:0};
const pitchOf=deg=>12*Math.tan(Math.max(0,Math.min(80,deg))*Math.PI/180);
const degOfPitch=p=>Math.atan(p/12)*180/Math.PI;
const fmtHalf=r=>r%1?r.toFixed(1):String(r);
const pitchLabel=p=>fmtHalf(Math.round(p*2)/2)+'/12';
const PG_MAX=60; // dial runs 0°–60° (flat to about 21/12)
function pgAngle(up){const [ux,uy,uz]=up;if(PG.mode==='roof')return Math.acos(Math.min(1,Math.abs(uz)/(Math.hypot(ux,uy,uz)||1)))*180/Math.PI;
  let a=Math.atan2(ux,uy)*180/Math.PI;if(a>90)a-=180;if(a<-90)a+=180;if(Math.abs(a)>.3)PG.sign=a<0?-1:1;return Math.abs(a)}
const pgTrim=a=>{if(!a.length)return null;const s=[...a].sort((x,y)=>x-y),k=Math.floor(s.length*.2),m=s.slice(k,s.length-k);const u=m.length?m:s;return u.reduce((x,y)=>x+y,0)/u.length};
// Filtering: trimmed mean of the last half second (throws out spikes), then an adaptive
// low-pass that follows real moves quickly but goes very still when the phone is still.
function pgSample(deg){PG.got=true;if(PG.locked||!isFinite(deg))return;const now=performance.now();
  PG.buf.push({t:now,d:deg});while(PG.buf.length&&now-PG.buf[0].t>1500)PG.buf.shift();
  const m=pgTrim(PG.buf.filter(s=>now-s.t<500).map(s=>s.d));
  const dt=Math.min(.2,PG.lastT?(now-PG.lastT)/1000:.016);PG.lastT=now;
  if(PG.est==null||now-PG.buf[0].t<450){PG.est=m;PG.shownP=null;PG.shownD=null}else{const diff=Math.abs(m-PG.est);const tau=diff>4?.1:diff>1.5?.3:.9;PG.est+=(m-PG.est)*dt/(tau+dt)}
  const win=PG.buf.filter(s=>now-s.t<1000).map(s=>s.d);let sd=99;
  if(win.length>10&&now-PG.buf[0].t>700){const mu=win.reduce((x,y)=>x+y,0)/win.length;sd=Math.sqrt(win.reduce((x,y)=>x+(y-mu)**2,0)/win.length)}
  PG.steady=sd<.7;PG.prog=PG.steady?Math.min(1,PG.prog+dt/1.1):Math.max(0,PG.prog-dt*1.5);
  PG.deg=PG.est;
  if(PG.prog>=1){PG.deg=pgTrim(win);PG.locked=true;PG.auto=true}
  pgPaint()}
function onOrient(e){if(e.beta==null||e.gamma==null)return;PG.orient=true;const b=e.beta*Math.PI/180,g=e.gamma*Math.PI/180;
  pgSample(pgAngle([-Math.cos(b)*Math.sin(g),Math.sin(b),Math.cos(b)*Math.cos(g)]))}
function onMotion(e){if(PG.orient)return;const a=e.accelerationIncludingGravity;if(!a||a.x==null)return;pgSample(pgAngle([a.x,a.y,a.z]))}
// The number only changes when the reading truly moves past the next half-step (no flicker).
function pgShown(){const p=pitchOf(PG.deg),r=Math.round(p*2)/2;
  if(PG.locked||PG.shownP==null||Math.abs(p-PG.shownP)>.4)PG.shownP=r;
  if(PG.locked||PG.shownD==null||Math.abs(PG.deg-PG.shownD)>.35)PG.shownD=Math.round(PG.deg*2)/2;
  return [PG.shownP,PG.shownD]}
function pgPaint(){if(!PG.raf)PG.raf=requestAnimationFrame(()=>{PG.raf=0;paintPitch()})}
function paintPitch(){const el=$('#layer .pg');if(!el)return;const [p,d]=pgShown();
  el.classList.toggle('locked',PG.locked);
  const v=$('#pg-val',el);if(v)v.innerHTML=`${fmtHalf(p)}<small>/12</small>`;
  const dg=$('#pg-deg',el);if(dg)dg.textContent=(PG.locked?PG.deg.toFixed(1):d.toFixed(1))+'°';
  const pct=Math.max(0,Math.min(1,PG.deg/PG_MAX));
  const f=$('#pg-fill',el);if(f)f.style.strokeDashoffset=String(100-pct*100);
  const k=$('#pg-knob',el);if(k)k.setAttribute('transform',`rotate(${(pct*180).toFixed(2)} 160 166)`);
  const lv=$('#pg-lvl',el);if(lv)lv.style.transform=`rotate(${(PG.sign*PG.deg).toFixed(2)}deg)`;
  const rf=$('#pg-rf',el);if(rf)rf.style.strokeDashoffset=String(100-(PG.locked?1:PG.prog)*100);
  const st=$('#pg-status',el),chip=$('#pg-chip',el);
  if(st)st.textContent=PG.locked?(PG.auto?'Locked':'Held'):!PG.got?'Waiting for sensors…':PG.prog>.15?'Hold it… locking':'Hold steady';
  if(chip)chip.classList.toggle('ok',PG.locked);
  const ok=$('#pg-ok',el);if(ok)ok.style.display=PG.locked?'':'none';
  const lk=$('#pg-lock',el);if(lk){lk.textContent=PG.locked?'Measure again':'Hold now';lk.classList.toggle('pri',!PG.leadId&&!PG.locked)}
  const us=$('[data-pg="use"]',el);if(us)us.classList.toggle('pri',true)}
async function startSensors(){
  try{for(const E of [window.DeviceOrientationEvent,window.DeviceMotionEvent]){if(E&&typeof E.requestPermission==='function'){const r=await E.requestPermission();if(r!=='granted'){toast('Motion access is off — allow it to use the pitch gauge');return false}}}}catch(e){}
  if(!PG.listening){window.addEventListener('deviceorientation',onOrient);window.addEventListener('devicemotion',onMotion);PG.listening=true}
  setTimeout(()=>{if(!PG.got&&$('#layer .pg'))toast('No sensor reading yet — this needs your phone, not a computer')},2500);return true}
async function startCam(){const v=$('#pg-video');if(!v)return;try{PG.stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}},audio:false});v.srcObject=PG.stream;await v.play().catch(()=>{});v.hidden=false}
  catch(e){toast('Camera didn’t open — you can still sight along the line');}}
function stopPitch(){if(PG.listening){window.removeEventListener('devicemotion',onMotion);window.removeEventListener('deviceorientation',onOrient);PG.listening=false}if(PG.stream){PG.stream.getTracks().forEach(t=>t.stop());PG.stream=null}$('#layer .pg')?.remove()}
function openPitch(leadId){PG.leadId=leadId;pgReset();PG.got=false;PG.orient=false;renderPitch()}
function pgReset(){Object.assign(PG,{locked:false,auto:false,est:null,buf:[],lastT:0,prog:0,steady:false,shownP:null,shownD:null})}
function pgDialSVG(){const cx=160,cy=166,R=138,pt=(pct,r)=>{const t=Math.PI*(1-pct);return [(cx+r*Math.cos(t)).toFixed(1),(cy-r*Math.sin(t)).toFixed(1)]};
  let ticks='';for(let p=0;p<=20;p++){const pct=degOfPitch(p)/PG_MAX;const maj=[0,3,6,9,12,18].includes(p);const [x1,y1]=pt(pct,R-20),[x2,y2]=pt(pct,R-(maj?32:26));
    ticks+=`<line class="pg-tick${maj?' maj':''}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`;if(maj){const [tx,ty]=pt(pct,R-46);ticks+=`<text class="pg-tl" x="${tx}" y="${ty}">${p}</text>`}}
  const arc=`M ${cx-R} ${cy} A ${R} ${R} 0 0 1 ${cx+R} ${cy}`;
  return `<svg viewBox="0 0 320 180" aria-hidden="true"><defs><linearGradient id="pgGrad" gradientUnits="userSpaceOnUse" x1="22" y1="0" x2="298" y2="0"><stop offset="0" stop-color="#FFB15C"/><stop offset="1" stop-color="#F2541B"/></linearGradient></defs>
    <path class="pg-track" d="${arc}"/><path id="pg-fill" class="pg-fill" d="${arc}" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100"/>${ticks}
    <g id="pg-knob"><circle class="pg-knob" cx="${cx-R}" cy="${cy}" r="11"/></g></svg>`}
const pgChip=`<div class="pg-chip" id="pg-chip"><svg viewBox="0 0 24 24" aria-hidden="true"><circle class="pg-rt" cx="12" cy="12" r="9"/><circle id="pg-rf" class="pg-rf" cx="12" cy="12" r="9" pathLength="100" stroke-dasharray="100" stroke-dashoffset="100"/><path id="pg-ok" d="M8 12.5l2.6 2.6L16 9.7" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" transform="rotate(90 12 12)" style="display:none"/></svg><span id="pg-status">Hold steady</span></div>`;
function renderPitch(){let el=$('#layer .pg');if(!el){el=document.createElement('div');el.className='pg';el.setAttribute('role','dialog');el.setAttribute('aria-modal','true');el.setAttribute('aria-label','Pitch gauge');$('#layer').appendChild(el)}
  const cam=PG.mode==='cam';
  el.innerHTML=`<div class="pg-top"><button class="pg-x" data-pg="close" aria-label="Close"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button><div class="pg-title">Pitch Gauge</div></div>
    <div class="pg-modes" role="tablist"><button role="tab" data-pg="roof" aria-selected="${!cam}">On the roof</button><button role="tab" data-pg="cam" aria-selected="${cam}">From the ground</button></div>
    <div class="pg-stage${cam?' cam':''}">${cam
      ?`<video id="pg-video" playsinline muted autoplay hidden></video><div class="pg-aim"><div id="pg-lvl" class="pg-lvl"></div><div class="pg-rake"></div><div class="pg-ring"></div><div class="pg-tagl"><span><i></i>Roof edge</span><span><i></i>Level</span></div></div>
        <div class="pg-card"><div class="pg-big" id="pg-val">0<small>/12</small></div><div class="pg-deg" id="pg-deg">0.0°</div>${pgChip}</div>`
      :`<div class="pg-dial">${pgDialSVG()}<div class="pg-readout"><div class="pg-big" id="pg-val">0<small>/12</small></div><div class="pg-deg" id="pg-deg">0.0°</div></div></div>${pgChip}`}</div>
    <p class="pg-help">${cam?'Face the gable end and hold the phone upright. Turn it until the orange line runs along the roof edge, then hold still — it locks on its own.'
      :'Lay the phone flat on the shingles, long edge pointing up the slope. Let go or hold still — it locks on its own.'}</p>
    <div class="pg-btns"><button class="pg-btn" id="pg-lock" data-pg="lock">Hold now</button>${PG.leadId?'<button class="pg-btn pri" data-pg="use">Save to roof</button>':''}</div>`;
  paintPitch();startSensors();if(cam)startCam();else if(PG.stream){PG.stream.getTracks().forEach(t=>t.stop());PG.stream=null}}
document.addEventListener('click',e=>{const b=e.target.closest('[data-pg]');if(!b)return;e.stopImmediatePropagation();const k=b.dataset.pg;
  if(k==='close'){stopPitch();return}
  if(k==='roof'||k==='cam'){if(PG.mode!==k){PG.mode=k;pgReset();renderPitch()}return}
  if(k==='lock'){if(PG.locked)pgReset();else if(PG.got){PG.locked=true;PG.auto=false}paintPitch();return}
  if(k==='use'){const l=S.leads.get(PG.leadId);if(!l)return;const p=Math.round(pitchOf(PG.deg)*2)/2;l.roof.pitch=pitchLabel(p);l.roof.calc=l.roof.calc||{};l.roof.calc.pitch=String(Math.round(p));
    saveLead(l);stopPitch();renderSheet();toast('Pitch saved: '+l.roof.pitch)}},true);
document.addEventListener('click',e=>{const b=e.target.closest('[data-act="pitchgauge"]');if(!b)return;e.stopImmediatePropagation();openPitch(S.open)},true);

window.__ridgeline={S,MV,ST,render,openLead,renderSheet};
boot();
