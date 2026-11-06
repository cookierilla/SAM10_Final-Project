// Shared header and footer, so every page has the same navigation.
const pages = [
  ['index.html', 'Summary'],
  ['infrastructure.html', 'Infrastructure'],
  ['system.html', 'System & card'],
  ['baseline.html', 'Baseline'],
  ['well-architected.html', 'Well-Architected'],
  ['operations.html', 'Monitoring · Backup · Security'],
  ['automation-incident.html', 'Automation & incident'],
  ['results.html', 'Results'],
  ['next-steps.html', 'Next steps'],
  ['declaration.html', 'Declaration'],
];
const here = location.pathname.split('/').pop() || 'index.html';
document.body.insertAdjacentHTML('afterbegin', `
<header class="site"><div class="inner">
  <a class="brand" href="index.html"><img src="assets/logo.svg" alt="">Kapé Lumen · SAM10 Final Project</a>
  <nav class="pages">${pages.map(([href, label]) =>
    `<a href="${href}"${href === here ? ' aria-current="page"' : ''}>${label}</a>`).join('')}</nav>
</div></header>`);
document.body.insertAdjacentHTML('beforeend', `
<footer class="site">
  Kapé Lumen is a fictional café; all data is invented. Built on
  <a href="https://github.com/danny-avila/LibreChat">LibreChat</a> (MIT, Danny Avila and contributors).
  Source: <a href="https://github.com/cookierilla/SAM10_Final-Project">github.com/cookierilla/SAM10_Final-Project</a>.
</footer>`);
