// Match selected files only; paths in a manifest never trigger a disk/network read.
export const logicalPath = value => String(value).replaceAll('\\', '/').replace(/^\.\//, '');
export function chooseFile(path, files) {
  const wanted = logicalPath(path);
  const exact = files.map((f, i) => [logicalPath(f.webkitRelativePath || f.name), i]).filter(([p]) => p === wanted);
  if (exact.length === 1) return exact[0][1];
  if (exact.length > 1) return -1;
  const basename = wanted.split('/').at(-1);
  const matches = files.map((f, i) => [logicalPath(f.webkitRelativePath || f.name).split('/').at(-1), i]).filter(([p]) => p === basename);
  return matches.length === 1 ? matches[0][1] : -1;
}
