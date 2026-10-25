document.addEventListener('DOMContentLoaded', () => {
  const slides = [...document.querySelectorAll('[data-ob-slide]')];
  if (!slides.length) return;
  const prev = document.querySelector('[data-ob-prev]');
  const next = document.querySelector('[data-ob-next]');
  const dots = document.querySelector('[data-ob-dots]');
  const bar = document.querySelector('[data-ob-progress]');
  let index = 0;
  bar.innerHTML = '<span></span>';
  slides.forEach((_, i) => {
    const dot = document.createElement('button');
    dot.type = 'button';
    dot.setAttribute('aria-label', `Folie ${i + 1}`);
    dot.addEventListener('click', () => show(i));
    dots.append(dot);
  });
  function show(i) {
    index = Math.max(0, Math.min(slides.length - 1, i));
    slides.forEach((slide, n) => { slide.hidden = n !== index; });
    [...dots.children].forEach((dot, n) => dot.setAttribute('aria-current', String(n === index)));
    bar.firstChild.style.width = `${((index + 1) / slides.length) * 100}%`;
    prev.disabled = index === 0;
    next.disabled = index === slides.length - 1;
  }
  prev.addEventListener('click', () => show(index - 1));
  next.addEventListener('click', () => show(index + 1));
  document.addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft') show(index - 1);
    if (event.key === 'ArrowRight') show(index + 1);
  });
  show(0);
});
