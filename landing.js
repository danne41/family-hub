(() => {
 const $=id=>document.getElementById(id);
 const overlay=$('auth-overlay');
 function openAuth(mode){
   overlay.classList.remove('hidden');
   window.FH_PENDING_AUTH_MODE=mode; $(mode==='register'?'tab-register':'tab-login').click();
   overlay.querySelector('input[name=email]').focus();
 }
 document.querySelectorAll('[data-auth-mode]').forEach(b=>b.addEventListener('click',()=>openAuth(b.dataset.authMode)));
 function close(){overlay.classList.add('hidden');}
 $('auth-close').addEventListener('click',close);
 $('auth-backdrop').addEventListener('click',close);
 document.addEventListener('keydown',e=>{if(e.key==='Escape')close();});
 document.querySelectorAll('[data-plan-interest]').forEach(b=>b.addEventListener('click',()=>{document.getElementById('pricing').scrollIntoView({behavior:'smooth'}); b.textContent='Kommer senare';}));
 function billing(year){
  $('price-year').classList.toggle('selected',year);$('price-month').classList.toggle('selected',!year);
  document.querySelectorAll('.price-amount strong').forEach(e=>{e.textContent=e.dataset[year?'year':'month']+' kr';e.nextElementSibling.textContent=year?'/år':'/månad';});
  document.querySelectorAll('.year-saving').forEach(e=>e.hidden=!year);
 }
 $('price-year').onclick=()=>billing(true);$('price-month').onclick=()=>billing(false);
 let offset=0, items=['Mjölk','Bröd','Frukt'];
 const monday=(d)=>{let x=new Date(d);x.setHours(12,0,0,0);x.setDate(x.getDate()-(x.getDay()+6)%7);return x;};
 function render(){
   const d=monday(new Date());d.setDate(d.getDate()+offset*7);
   const end=new Date(d);end.setDate(d.getDate()+6);
   $('demo-week').textContent=`${d.toLocaleDateString('sv-SE',{day:'numeric',month:'short'})} – ${end.toLocaleDateString('sv-SE',{day:'numeric',month:'short'})}`;
   $('demo-days').replaceChildren();
   ['Mån','Tis','Ons','Tor','Fre','Lör','Sön'].forEach((day,i)=>{const el=document.createElement('div');const b=document.createElement('b');b.textContent=day;const n=document.createElement('span');n.textContent=d.getDate()+i>new Date(d.getFullYear(),d.getMonth()+1,0).getDate()?'•':String(new Date(d.getFullYear(),d.getMonth(),d.getDate()+i).getDate());el.append(b,n);$('demo-days').append(el);});
   $('demo-list').replaceChildren();
   items.forEach((item,i)=>{const li=document.createElement('li');const cb=document.createElement('input');cb.type='checkbox';const span=document.createElement('span');span.textContent=item;const del=document.createElement('button');del.type='button';del.textContent='Ta bort';del.addEventListener('click',()=>{items.splice(i,1);render();});li.append(cb,span,del);$('demo-list').append(li);});
 }
 $('demo-prev').onclick=()=>{offset--;items=[];render();};
 $('demo-next').onclick=()=>{offset++;items=[];render();};
 $('demo-form').addEventListener('submit',e=>{e.preventDefault();const v=$('demo-item').value.trim();if(v){items.push(v);$('demo-item').value='';render();}});
 render();
 if(location.hash==='#register')openAuth('register');
 if(location.hash==='#login')openAuth('login');
})();