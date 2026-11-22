// Förhandsgränssnitt: inga OAuth-flöden eller tokens lagras här.
document.querySelectorAll('[data-sync-provider]').forEach(button => {
  button.addEventListener('click', () => {
    const provider = button.dataset.syncProvider;
    const status = document.getElementById('sync-status');
    status.textContent = `${provider}: riktig anslutning kommer i en senare version. Ingen kalender har anslutits och ingen data delas.`;
  });
});
