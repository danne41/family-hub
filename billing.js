// Family Hub test billing – never put Stripe secret keys in the browser.
(()=>{
 const prices={plus:{month:'price_1UeZokDHyA40vHHZfdf1YLJv',year:'price_1UeZrDDHyA40vHHZNtj3nqLS'},premium_family:{month:'price_1UeZsrDHyA40vHHZHasgi7rX',year:'price_1UeZu9DHyA40vHHZKanc2Yhx'}};
 const note=document.createElement('p');note.id='billing-notice';note.setAttribute('role','status');note.className='muted';
 const pricing=document.getElementById('pricing');pricing?.append(note);
 async function call(name,payload={}){
  const client=window.FH?.client;
  if(!client||!window.FH?.user)throw Error('Logga in först.');
  const {data,error}=await client.functions.invoke(name,{body:payload});
  if(error)throw Error(error.message||'Anslutningen misslyckades');
  if(!data?.url||!/^https:\/\/[^/]*stripe\.com\//.test(data.url))throw Error(data?.error||'Stripe returnerade ingen giltig betalningslänk.');
  location.assign(data.url);
 }
 let pending=null;
 const buttons=[...document.querySelectorAll('[data-plan-interest]')];
 for(const btn of buttons){const plan=btn.dataset.planInterest==='Plus'?'plus':'premium_family';btn.textContent='Välj abonnemang';btn.removeAttribute('data-plan-interest');btn.addEventListener('click',async()=>{
  const year=document.getElementById('price-year')?.classList.contains('selected');const priceId=prices[plan][year?'year':'month'];
  if(!window.FH?.user){pending=priceId;note.textContent='Logga in för att fortsätta till säker betalning.';document.querySelector('[data-auth-mode="login"]')?.click();return;}
  btn.disabled=true;note.textContent='Öppnar Stripe i testläge…';try{await call('billing-checkout',{priceId})}catch(e){note.textContent=e.message}finally{btn.disabled=false}
 });}
 document.addEventListener('fh-auth',async()=>{if(pending&&window.FH?.user){const priceId=pending;pending=null;note.textContent='Öppnar Stripe i testläge…';try{await call('billing-checkout',{priceId})}catch(e){note.textContent=e.message}}});
 const profile=document.getElementById('profile');if(profile){
 profile.querySelectorAll('.billing-profile-card').forEach(el=>el.remove());const card=document.createElement('div');card.className='card billing-profile-card';const h=document.createElement('h2');h.textContent='Mitt abonnemang';const state=document.createElement('p');state.className='muted';state.textContent='Free – inget aktivt abonnemang';const upgrade=document.createElement('button');upgrade.type='button';upgrade.textContent='Se planer och uppgradera';upgrade.addEventListener('click',()=>document.querySelector('nav [data-view="pricing"]')?.click());const manage=document.createElement('button');manage.hidden=true;manage.type='button';manage.className='secondary';manage.textContent='Hantera abonnemang';manage.onclick=async()=>{manage.disabled=true;state.textContent='Öppnar Stripe…';try{await call('billing-portal')}catch(e){state.textContent=e.message}finally{manage.disabled=false}};card.append(h,state,upgrade,manage);profile.append(card);
 const update=async()=>{if(!window.FH?.user||!window.FH?.client){state.textContent='Logga in för att se abonnemang.';return;}const {data,error}=await window.FH.client.from('billing_subscriptions').select('plan,status,current_period_end,cancel_at_period_end').eq('user_id',window.FH.user.id).order('updated_at',{ascending:false}).limit(1);if(error){state.textContent='Abonnemangsstatus kunde inte hämtas.';return;}const sub=data?.[0];if(!sub){state.textContent='Free – inget aktivt abonnemang';manage.hidden=true;upgrade.hidden=false;return;}const label=sub.plan==='premium_family'?'Premium Family':sub.plan==='plus'?'Plus':sub.plan;state.textContent=label+' · '+sub.status+(sub.cancel_at_period_end?' · Avslutas vid periodslut':'');manage.hidden=false;upgrade.hidden=false;};
 document.addEventListener('fh-auth',()=>setTimeout(update,150));document.querySelector('nav [data-view="profile"]')?.addEventListener('click',update);setTimeout(update,800);
 }
 const query=new URLSearchParams(location.search);if(query.has('billing')){note.textContent=query.get('billing')==='success'?'Du är tillbaka från Stripe. Abonnemanget aktiveras efter bekräftelse.':'Betalningen avbröts eller abonnemangshanteringen avslutades.';history.replaceState(null,'',location.pathname+location.hash)}
})();
