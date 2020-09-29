import { NowRequest, NowResponse } from "@vercel/node";
import fetch from "isomorphic-unfetch";
import shuffle from "lodash/shuffle";
import { WebClient } from "@slack/web-api";
import { verifyRequestSignature } from '@slack/events-api';
import getRawBody from "raw-body";

const kDeleteCommand = /.*delete.*/gi;
const kMemeCommand = /.*me.*irl.*/gi;
const kSubreddits = ["me_irl", "meirl", "wholesomememes"];

const slack = new WebClient(process.env.BOT_OAUTH_TOKEN);

// we can assume that serverless will nuke this in-memory cache at least every 30s
// but parallel execution might fuck us up yay thread safety
let memes: string[] = [];
let channelId = null; // keep track of the channel this app is receiving messages on

// track previous message ids so that we can delete them later
const pastMessageIds = [];

const hotEndpointForSubreddit = (sub: string) =>
  `https://www.reddit.com/r/${sub}.json?count=500`;

// ask our subreddits for memes and reduce them
const refreshMemes = async () => {
  const results = await Promise.all(
    kSubreddits.map(hotEndpointForSubreddit).map(url =>
      fetch(url, {
        headers: { "User-Agent": "me_irl_bot by /u/shrugs" }
      }).then(res => res.json())
    )
  );

  const urls: string[] = results.reduce(
    (memo, result) => [
      ...memo,
      ...result.data.children //
        .filter(child => child.kind === "t3") // idk
        .map(child => child.data) // pull data
        .filter(data => !data.is_self) // no self posts
        .filter(data => !data.hidden) // no hidden posts (?)
        .filter(data => !data.over_18) // SWF only please
        .map(data => data.url) // pull url
    ],
    []
  );

  memes = shuffle(urls);
};

const postMeme = async () => {
  if (memes.length === 0) {
    // we don't have a meme, no-op
    console.log("no meme available!");
    return;
  }

  const imageUrl = memes.pop();

  console.log(`posting ${imageUrl}`);

  // post a meme and add its message id to the stack
  const res = await slack.chat.postMessage({
    channel: channelId,
    text: imageUrl,
    // eslint-disable-next-line @typescript-eslint/camelcase
    unfurl_links: true,
    // eslint-disable-next-line @typescript-eslint/camelcase
    unfurl_media: true
  });

  pastMessageIds.push(res.ts);
};

const deleteLastMessage = async () => {
  if (pastMessageIds.length === 0) {
    throw new Error("no latest ts to delete");
  }

  const ts = pastMessageIds.pop();

  console.log(`deleting ${ts}`);

  await slack.chat.delete({ channel: channelId, ts });
};

const main = async (
  req: NowRequest
): Promise<void | object> => {
  console.log(`req.body: ${JSON.stringify(req.body)}`);
  // no body? get outta here.
  if (!req.body) {
    throw new Error("No request body provided.");
  }

  const body = await getRawBody(req);

  const isValid = verifyRequestSignature({
    signingSecret: process.env.SLACK_SIGNING_SECRET,
    body: body.toString(),
    requestSignature: req.headers['x-slack-signature'] as string,
    requestTimestamp: parseInt(req.headers['x-slack-request-timestamp'] as string, 10),
  })

  if (!isValid) {
    throw new Error("Invalid request from slack!")
  }

  // handle url verification challenges
  if (req.body.type === "url_verification") {
    return { challenge: req.body.challenge };
  }

  // if this isn't an event callback, ignore it
  if (req.body.type !== "event_callback") {
    return;
  }

  const { event } = req.body;

  // if this isn't a message, we don't care
  if (event.type !== "message") {
    throw new Error(`unknown message type ${req.body.type}`);
  }

  // we don't need to do anything for message subtypes, since those will not be plain old messages
  if (event.subtype) {
    return;
  }

  const text = event.text as string;

  // are we requesting a meme?
  if (kMemeCommand.test(text)) {
    channelId = event.channel;
    // do we have any memes to send?
    if (memes.length === 0) {
      // we have no memes!
      await refreshMemes();
    }

    await postMeme();
    return;
  }

  if (kDeleteCommand.test(text)) {
    await deleteLastMessage();
    return;
  }

  return;
};

export default async (req: NowRequest, res: NowResponse) => {
  res.status(200);

  try {
    const body = await main(req);
    if (body) {
      res.json(body);
    } else {
      res.status(200).end();
    }
  } catch (error) {
    console.error(error);
    res.status(500).json({error: error.toString()})
  }
};

export const config = {
  api: {
    bodyParser: false,
  },
};
