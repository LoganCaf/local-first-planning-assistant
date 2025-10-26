import { createApp } from './app.js';

const PORT = Number(process.env.PORT ?? 4000);
const { server } = createApp();

server.listen(PORT, () => {
  console.log(`Server listening on http://localhost:${PORT}`);
});
