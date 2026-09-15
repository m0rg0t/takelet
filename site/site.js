const copyButton = document.getElementById('copy-commands');
const commands = document.getElementById('build-commands');
const copyStatus = document.getElementById('copy-status');

if (copyButton && commands && copyStatus && navigator.clipboard?.writeText) {
  copyButton.hidden = false;
  copyButton.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(commands.textContent.trim());
      copyStatus.textContent = 'Copied to clipboard';
    } catch {
      copyStatus.textContent = 'Select the commands to copy them.';
    }
  });
}
