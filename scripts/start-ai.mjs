import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const backend = fileURLToPath(new URL('../backend/', import.meta.url));
console.log('正在启动 PersonalCloakRoom AI 换装后端…');
const child = spawn('go', ['run', 'main.go'], {
  cwd: backend,
  env: process.env,
  stdio: 'inherit',
});
child.on('error', () => {
  console.error('无法启动 Go 后端，请检查 Go 是否已安装。');
  process.exitCode = 1;
});
child.on('exit', code => { process.exitCode = code ?? 1; });
