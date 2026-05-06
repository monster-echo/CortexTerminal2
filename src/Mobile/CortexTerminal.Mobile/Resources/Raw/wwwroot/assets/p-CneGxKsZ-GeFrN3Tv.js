import{W as r,f as s,e as i,P as a,m}from"./index-CVPlekZi.js";/*!
 * (C) Ionic http://ionicframework.com - MIT License
 */const c=()=>{const t=window;t.addEventListener("statusTap",(()=>{r((()=>{const n=document.elementFromPoint(t.innerWidth/2,t.innerHeight/2);if(!n)return;const e=s(n);e&&new Promise((o=>i(e,o))).then((()=>{a((async()=>{e.style.setProperty("--overflow","hidden"),await m(e,300),e.style.removeProperty("--overflow")}))}))}))}))};export{c as startStatusTap};
