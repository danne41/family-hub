// Compact navigation for tablet portrait and phones. No authentication changes.
(()=>{
 const shell=document.getElementById('app-shell');
 const toggle=document.getElementById('mobile-menu-toggle');
 const nav=document.getElementById('app-primary-nav');
 if(!shell||!toggle||!nav)return;
 const close=()=>{shell.classList.remove('menu-open');toggle.setAttribute('aria-expanded','false');toggle.textContent='☰ Meny';};
 toggle.addEventListener('click',()=>{const open=!shell.classList.contains('menu-open');shell.classList.toggle('menu-open',open);toggle.setAttribute('aria-expanded',String(open));toggle.textContent=open?'✕ Stäng':'☰ Meny';});
 nav.addEventListener('click',e=>{if(e.target.closest('button[data-view]'))close();});
 document.getElementById('sidebar-signout')?.addEventListener('click',close);
 document.addEventListener('keydown',e=>{if(e.key==='Escape')close();});
 window.matchMedia('(min-width: 1025px)').addEventListener('change',e=>{if(e.matches)close();});
})();
