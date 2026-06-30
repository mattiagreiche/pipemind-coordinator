const { Client, GatewayIntentBits, Events } = require('discord.js');

const N8N_BASE = process.env.N8N_WEBHOOK_BASE || 'http://n8n:5678/webhook';
const BOT_TOKEN = process.env.DISCORD_BOT_TOKEN;
const TL_CHANNEL_ID = process.env.TL_CHANNEL_ID;
const CLIENT_CHANNEL_ID = process.env.CLIENT_CHANNEL_ID;

const WH_TL        = 'tl-interaction';
const WH_CLIENT_QA = 'client-qa';
const WH_MEMBER    = 'member-join';
const WH_DEV       = 'dev-query';

if (!BOT_TOKEN) {
  console.error('[forwarder] DISCORD_BOT_TOKEN is not set — exiting');
  process.exit(1);
}

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.DirectMessages,
  ],
});

async function post(path, body) {
  const url = `${N8N_BASE}/${path}`;
  try {
    const { default: fetch } = await import('node-fetch');
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      console.warn(`[forwarder] POST ${url} → ${res.status}`);
    }
  } catch (err) {
    console.error(`[forwarder] POST ${url} failed:`, err.message);
  }
}

// Discord Gateway format expected by n8n Filter nodes: { t, d }
function gatewayEnvelope(type, d) {
  return { t: type, d };
}

client.once(Events.ClientReady, () => {
  console.log(`[forwarder] Connected as ${client.user.tag}`);
});

client.on(Events.MessageCreate, async (message) => {
  if (message.author.bot) return;

  const d = {
    id: message.id,
    channel_id: message.channelId,
    guild_id: message.guildId || undefined,
    author: {
      id: message.author.id,
      username: message.author.username,
      bot: false,
    },
    content: message.content,
    webhook_id: undefined,
    timestamp: new Date(message.createdTimestamp).toISOString(),
  };

  const payload = gatewayEnvelope('MESSAGE_CREATE', d);
  const channelId = message.channelId;
  const isDM = !message.guildId;

  // TL channel → workflow 03
  if (channelId === TL_CHANNEL_ID) {
    await post(WH_TL, payload);
    return;
  }

  // Client channel → workflow 05
  if (channelId === CLIENT_CHANNEL_ID) {
    await post(WH_CLIENT_QA, payload);
    return;
  }

  // DMs → workflow 07 (developer query)
  if (isDM) {
    await post(WH_DEV, payload);
  }
});

client.on(Events.GuildMemberAdd, async (member) => {
  const d = {
    user: {
      id: member.user.id,
      username: member.user.username,
    },
    guild_id: member.guild.id,
    joined_at: member.joinedAt ? member.joinedAt.toISOString() : null,
  };
  await post(WH_MEMBER, gatewayEnvelope('GUILD_MEMBER_ADD', d));
});

client.login(BOT_TOKEN);
