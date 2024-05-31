#!/usr/bin/env bun
import { $ } from "bun";
import Bun from "bun";
import { parseArgs } from "util";
import { existsSync } from "node:fs";
import { resolve } from "path";
import { cwd, platform } from "node:process";

console.log("mill");
const isWin = process.platform === "win32";
const millCmd = isWin
  ? resolve(__dirname, "bin", "mill.bat")
  : resolve(__dirname, "bin", "mill");
const args = process.argv.slice(2);  

$`${millCmd} $args`;
