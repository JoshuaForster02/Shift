const gear = document.querySelector('#demo-gear');
const feedback = document.querySelector('#demo-feedback');
let value = 16;
function change(delta, button) {
  value = Math.max(1, Math.min(30, value + delta));
  gear.value = String(value);
  gear.textContent = String(value);
  feedback.textContent = `${delta > 0 ? 'Hochgeschaltet' : 'Runtergeschaltet'} · Demo-Gang ${value}`;
  button.classList.add('is-active');
  setTimeout(() => button.classList.remove('is-active'), 160);
}
document.querySelector('#demo-up').addEventListener('click', event => change(1, event.currentTarget));
document.querySelector('#demo-down').addEventListener('click', event => change(-1, event.currentTarget));
if (location.hash === '#erster-start') document.querySelector('#erster-start').open = true;
document.querySelectorAll('a[href="#erster-start"]').forEach(link => link.addEventListener('click', () => {
  document.querySelector('#erster-start').open = true;
}));
