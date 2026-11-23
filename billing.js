// Famunova test-mode billing draft. Group selection is explicit; never infer a family.
(()=>{
 const prices={plus:{month:'price_1UeZokDHyA40vHHZfdf1YLJv',year:'price_1UeZrDDHyA40vHHZNtj3nqLS'},premium_family:{month:'price_1UeZsrDHyA40vHHZHasgi7rX',year:'price_1UeZu9DHyA40vHHZKanc2Yhx'}};
 const pricing=document.getElementById('pricing');
 const note=document.createElement('p');note.id='billing-notice';note.className='muted';note.setAttribute('role','status');pricing?.append(note);
 const picker=document.createElement('label');picker.textContent='Familj som ska få abonnemanget ';
 const select=document.createElement('select');select.id='billing-family-select';select.setAttribute('aria-label','Välj familj för abonnemang');picker.append(select);pricing?.insertBefore(picker,note);
 const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);
 let chosen=null;
 const ownGroups=()=>Array.isArray(window.FH?.groups)&&window.FH?.user?window.FH.groups.filter(g=>g.owner_id===window.FH.user.id&&uuid(g.id)):[];
 function refresh(){
  const groups=ownGroups();const previous=chosen;
  select.replaceChildren(new Option('Välj familjegrupp…',''));
  for(const g of groups)select.add(new Option(g.name,g.id));
  chosen=groups.some(g=>g.id===previous)?previous:null;
  select.value=chosen||'';
  picker.hidden=!window.FH?.user;
  if(window.FH?.user&&!groups.length)note.textContent='Skapa en familjegrupp som du äger innan du väljer abonnemang.';
 }
 select.addEventListener('change',()=>{chosen=ownGroups().some(g=>g.id===select.value)?select.value:null;renderStatus();});
 function selectedGroup(){
  if(!chosen||!ownGroups().some(g=>g.id===chosen))throw Error('Välj först vilken familjegrupp du vill uppgradera.');
  return chosen;
 }
 function stripeUrl(raw){
  const u=new URL(raw);
  if(u.protocol!=='https:'||!['checkout.stripe.com','billing.stripe.com'].includes(u.hostname)||u.username||u.password)throw Error('Ogiltig Stripe-länk.');
  return u.href;
 }
 async function call(name,payload){
  const client=window.FH?.client;if(!client||!window.FH?.user)throw Error('Logga in först.');
  const {data,error}=await client.functions.invoke(name,{body:payload});
  if(error)throw Error(error.message||'Anslutningen misslyckades');
  if(!data?.url)throw Error(data?.error||'Ingen betalningslänk mottogs.');
  location.assign(stripeUrl(data.url));
 }
 for(const btn of document.querySelectorAll('[data-plan-interest]')){
  const plan=btn.dataset.planInterest==='Plus'?'plus':'premium_family';
  btn.textContent='Välj abonnemang';btn.removeAttribute('data-plan-interest');
  btn.addEventListener('click',async()=>{
   if(!window.FH?.user){note.textContent='Logga in och välj en familj för att fortsätta.';document.querySelector('[data-auth-mode="login"]')?.click();return;}
   let groupId;try{groupId=selectedGroup();}catch(e){note.textContent=e.message;select.focus();return;}
   const yearly=document.getElementById('price-year')?.classList.contains('selected');
   btn.disabled=true;note.textContent='Öppnar Stripe i testläge…';
   try{await call('billing-checkout',{groupId,priceId:prices[plan][yearly?'year':'month']});}
   catch(e){note.textContent=e.message;}finally{btn.disabled=false;}
  });
 }
 const profile=document.getElementById('profile');let state,manage,upgrade;
 if(profile){
  profile.querySelectorAll('.billing-profile-card').forEach(x=>x.remove());
  const card=document.createElement('div');card.className='card billing-profile-card';
  const title=document.createElement('h2');title.textContent='Familjens abonnemang';
  state=document.createElement('p');state.className='muted';
  upgrade=document.createElement('button');upgrade.type='button';upgrade.textContent='Se planer och välj familj';
  upgrade.addEventListener('click',()=>document.querySelector('nav [data-view="pricing"]')?.click());
  manage=document.createElement('button');manage.type='button';manage.className='secondary';manage.textContent='Hantera vald familjs abonnemang';manage.hidden=true;
  manage.addEventListener('click',async()=>{let groupId;try{groupId=selectedGroup();}catch(e){state.textContent=e.message;return;}manage.disabled=true;try{await call('billing-portal',{groupId});}catch(e){state.textContent=e.message;}finally{manage.disabled=false;}});
  card.append(title,state,upgrade,manage);profile.append(card);
 }
 let statusSequence=0;
 async function renderStatus(){
  const seq=++statusSequence;
  if(!state)return;
  manage.hidden=true;
  if(!window.FH?.user){state.textContent='Logga in för att se familjens abonnemang.';return;}
  if(!chosen){state.textContent='Välj en familj i abonnemangssektionen för att se dess status.';return;}
  const groupId=chosen;state.textContent='Hämtar abonnemang…';
  const {data,error}=await window.FH.client.from('billing_subscriptions')
   .select('plan,status,current_period_end,cancel_at_period_end')
   .eq('group_id',groupId).eq('user_id',window.FH.user.id).order('updated_at',{ascending:false}).limit(1);
  if(seq!==statusSequence||chosen!==groupId)return;
  if(error){state.textContent='Kunde inte läsa abonnemanget.';return;}
  const sub=data?.[0];if(!sub){state.textContent='Free – inget abonnemang registrerat för vald familj.';return;}
  const label=sub.plan==='premium_family'?'Premium Family':sub.plan==='plus'?'Plus':sub.plan;
  state.textContent=label+' · '+sub.status+(sub.cancel_at_period_end?' · Avslutas vid periodslut':'');
  manage.hidden=false;
 }
 document.addEventListener('fh-auth',()=>{chosen=null;refresh();renderStatus();});
 document.addEventListener('fh-groups',()=>{refresh();renderStatus();});
 document.querySelector('nav [data-view="profile"]')?.addEventListener('click',renderStatus);
 refresh();renderStatus();
 const query=new URLSearchParams(location.search);
 if(query.has('billing')){
  note.textContent=query.get('billing')==='success'?'Tillbaka från Stripe. Abonnemanget uppdateras först efter verifierad webhook.':'Stripe-flödet avslutades.';
  history.replaceState(null,'',location.pathname+location.hash);
 }
})();
