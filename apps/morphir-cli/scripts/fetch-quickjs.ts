import { downloadRelease } from "@terascope/fetch-github-release";
import os from "node:os";

const user = "quickjs-ng";
const repo = "quickjs";
const outputDir = "out/quickjs/";
const leaveZipped = false;
const disableLogging = false;

function filterRelease(release) {
  return release.prerelease === false;
}

function filterAsset(asset) {
  const platform = os.platform();
  if (asset.name.includes("wasi")) return true;
  if (asset.name.includes(platform)) return true;
  return false;
}

async function fetch() {
  try {
    await downloadRelease(
      user,
      repo,
      outputDir,
      filterRelease,
      filterAsset,
      leaveZipped,
      disableLogging
    );
    console.log("QuickJS downloaded successfully");
  } catch (error) {
    console.error("Error downloading QuickJS", error);
  }
}

await fetch();
