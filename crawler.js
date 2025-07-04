#!/usr/bin/env node

const fs = require("fs");

const AUTH_TOKEN = process.env.AUTH_TOKEN;
if (!AUTH_TOKEN) {
  console.error("AUTH_TOKEN is not set");
  process.exit(1);
}

const UPDATE_GIST = process.env.UPDATE_GIST;
const UPDATE_FS = process.env.UPDATE_FS;

const GITHUB_API_BASE = "https://api.github.com";
const OUTPUT_FILE = "store.nvim-repos.json";
const GIST_ID = "93dcd3ce38cbc7a0b3245b9b59b56c9b";
const GIST_URL = `https://gist.github.com/alex-popov-tech/${GIST_ID}`;
const githubUrlRegex = /https:\/\/github\.com\/([^\/\s\)]+)\/([^\/\s\)]+)/g;
const awesomeNeovimCollectionUrl = `${GITHUB_API_BASE}/repos/rockerBOO/awesome-neovim`;

async function req(method, url, data = null) {
  try {
    const options = {
      method,
      headers: {
        "User-Agent": "awesome-neovim-crawler",
        Accept: "application/vnd.github.v3+json",
        Authorization: `Bearer ${AUTH_TOKEN}`,
      },
    };

    if (data) {
      options.headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(data);
    }

    const response = await fetch(url, options);

    if (response.ok) {
      const responseData = await response.json();
      return { success: true, data: responseData };
    } else {
      let errorBody;
      try {
        errorBody = await response.json();
      } catch {
        errorBody = await response.text();
      }

      console.error(
        `HTTP ${response.status} (${response.statusText}) for ${url}`,
      );
      if (errorBody?.message) {
        console.error(`Error: ${errorBody.message}`);
      } else if (typeof errorBody === "string" && errorBody.trim()) {
        console.error(
          `Response: ${errorBody.substring(0, 200)}${errorBody.length > 200 ? "..." : ""}`,
        );
      }

      return {
        success: false,
        error: {
          statusCode: response.status,
          statusMessage: response.statusText,
          body: errorBody,
        },
      };
    }
  } catch (error) {
    console.error(`Network error for ${url}: ${error.message}`);
    return {
      success: false,
      error: {
        networkError: error.message,
      },
    };
  }
}

async function getRepoReadme(url) {
  console.log(`Fetching content from ${url}...`);
  const response = await req("GET", `${url}/readme`);

  if (!response.success) {
    console.error(`FATAL: Failed to fetch content from ${url}`);
    if (response.error) {
      console.error("Error details:", JSON.stringify(response.error, null, 2));
    }
    process.exit(1);
  }

  const content = Buffer.from(response.data.content, "base64").toString(
    "utf-8",
  );
  return content;
}

async function getRepoInfo(owner, repo) {
  console.log(`Fetching ${owner}/${repo}...`);

  const url = `${GITHUB_API_BASE}/repos/${owner}/${repo}`;
  const response = await req("GET", url);

  if (!response.success) {
    console.error(`Failed to fetch repository info for ${owner}/${repo}`);
    return null;
  }

  const info = response.data;

  return {
    full_name: info.full_name,
    description: info.description || "",
    homepage: info.homepage || "",
    html_url: info.html_url,
    stargazers_count: info.stargazers_count,
    watchers_count: info.watchers_count,
    fork_count: info.forks_count,
    updated_at: info.updated_at,
    topics: info.topics || [],
  };
}

async function updateGist(gistId, content) {
  console.log("Updating GitHub gist...");

  const url = `${GITHUB_API_BASE}/gists/${gistId}`;
  const data = {
    files: {
      "store.nvim-repos.json": {
        content: JSON.stringify(content, null, 2),
      },
    },
  };

  const response = await req("PATCH", url, data);

  if (response.success) {
    console.log(`✓ Gist updated successfully: ${GIST_URL}`);
    return true;
  } else {
    console.error("FATAL: Failed to update gist");
    if (response.error) {
      console.error("Error details:", JSON.stringify(response.error, null, 2));
    }
    process.exit(1);
  }
}

function grabPluginsFromReadme(readmeContent) {
  console.log("Extracting repository URLs...");
  const contentsIndex = readmeContent.indexOf("## Contents");
  const contentAfterContents =
    contentsIndex !== -1
      ? readmeContent.substring(contentsIndex)
      : readmeContent;

  const urls = new Set();
  let match;

  while ((match = githubUrlRegex.exec(contentAfterContents)) !== null) {
    const [, owner, repo] = match;
    if (owner !== "github" && !repo.includes("#") && !repo.includes("?")) {
      urls.add(`${owner}/${repo}`);
    }
  }
  return [...urls];
}

async function main() {
  const readmeContent = await getRepoReadme(awesomeNeovimCollectionUrl);

  const pluginUrls = grabPluginsFromReadme(readmeContent);
  console.log(`Found ${pluginUrls.length} unique repositories`);

  const repositories = [];

  for (let i = 0; i < pluginUrls.length; i++) {
    const [owner, repo] = pluginUrls[i].split("/");
    const repoInfo = await getRepoInfo(owner, repo);

    if (repoInfo) {
      repositories.push(repoInfo);
    }
    console.log(`Progress: ${i + 1}/${pluginUrls.length}`);
  }

  const output = {
    crawled_at: new Date().toISOString(),
    total_repositories: repositories.length,
    repositories: repositories,
  };

  if (UPDATE_FS) {
    fs.writeFileSync(OUTPUT_FILE, JSON.stringify(output, null, 2));
    console.log(`✓ Local file saved: ${OUTPUT_FILE}`);
  }

  if (UPDATE_GIST) {
    await updateGist(GIST_ID, output);
  }
  console.log(`\nComplete! ${repositories.length} repositories processed:`);
}

main().catch((error) => {
  console.error("Error:", error.message);
  process.exit(1);
});
