#!/usr/bin/env node

/**
 * Sync Rust Crate Versions from Changesets
 *
 * This script is called after `changeset version` to synchronize
 * version changes to Rust Cargo.toml files and mobile app configs.
 *
 * It reads the version from the desktop UI package.json (which changesets
 * manages) and applies it to all Rust crates.
 */

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = join(__dirname, '..', '..');

// Read version from desktop UI package.json (managed by changesets)
function getTargetVersion() {
  const pkgPath = join(ROOT_DIR, 'code', 'vauchi-desktop', 'ui', 'package.json');

  if (!existsSync(pkgPath)) {
    // Fall back to root package.json
    const rootPkgPath = join(ROOT_DIR, 'package.json');
    if (existsSync(rootPkgPath)) {
      const pkg = JSON.parse(readFileSync(rootPkgPath, 'utf8'));
      return pkg.version || '0.1.0';
    }
    return '0.1.0';
  }

  const pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
  return pkg.version;
}

// Update version in a Cargo.toml file
function updateCargoToml(filePath, version) {
  if (!existsSync(filePath)) {
    return false;
  }

  let content = readFileSync(filePath, 'utf8');
  const originalContent = content;

  // Update version in [package] section
  // Match: version = "x.y.z" (only at start of line in package section)
  content = content.replace(
    /^(version\s*=\s*")[^"]+(")/m,
    `$1${version}$2`
  );

  if (content !== originalContent) {
    writeFileSync(filePath, content);
    return true;
  }
  return false;
}

// Update Android version
function updateAndroidVersion(version) {
  const gradlePath = join(ROOT_DIR, 'android', 'app', 'build.gradle.kts');

  if (!existsSync(gradlePath)) {
    console.log('  Android gradle file not found, skipping');
    return;
  }

  let content = readFileSync(gradlePath, 'utf8');
  const originalContent = content;

  // Update versionName
  content = content.replace(
    /versionName\s*=\s*"[^"]+"/,
    `versionName = "${version}"`
  );

  // Increment versionCode
  const versionCodeMatch = content.match(/versionCode\s*=\s*(\d+)/);
  if (versionCodeMatch) {
    const currentCode = parseInt(versionCodeMatch[1], 10);
    const newCode = currentCode + 1;
    content = content.replace(
      /versionCode\s*=\s*\d+/,
      `versionCode = ${newCode}`
    );
    console.log(`  Incremented Android versionCode to ${newCode}`);
  }

  if (content !== originalContent) {
    writeFileSync(gradlePath, content);
    console.log(`  Updated: ${gradlePath}`);
  }
}

// Update iOS version (requires PlistBuddy on macOS)
function updateIOSVersion(version) {
  const plistPath = join(ROOT_DIR, 'ios', 'Vauchi', 'Info.plist');

  if (!existsSync(plistPath)) {
    console.log('  iOS plist file not found, skipping');
    return;
  }

  try {
    // Check if PlistBuddy is available (macOS only)
    execSync('which /usr/libexec/PlistBuddy', { stdio: 'ignore' });

    // Update CFBundleShortVersionString
    execSync(
      `/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "${plistPath}"`,
      { stdio: 'inherit' }
    );

    // Get and increment CFBundleVersion
    const currentBuild = execSync(
      `/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${plistPath}"`,
      { encoding: 'utf8' }
    ).trim();

    const newBuild = parseInt(currentBuild, 10) + 1;
    execSync(
      `/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${newBuild}" "${plistPath}"`,
      { stdio: 'inherit' }
    );

    console.log(`  Updated iOS version to ${version} (build ${newBuild})`);
  } catch (e) {
    console.log('  PlistBuddy not available (not macOS), skipping iOS update');
  }
}

// Find all Cargo.toml files in code/
function findCargoFiles() {
  const codeDir = join(ROOT_DIR, 'code');
  const cargoFiles = [];

  function walk(dir) {
    const entries = readdirSync(dir, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = join(dir, entry.name);

      if (entry.isDirectory() && entry.name !== 'target' && entry.name !== 'node_modules') {
        walk(fullPath);
      } else if (entry.isFile() && entry.name === 'Cargo.toml') {
        cargoFiles.push(fullPath);
      }
    }
  }

  if (existsSync(codeDir)) {
    walk(codeDir);
  }

  return cargoFiles;
}

// Main
function main() {
  console.log('Syncing Rust crate versions from changesets...');
  console.log('='.repeat(50));

  const version = getTargetVersion();
  console.log(`Target version: ${version}`);
  console.log();

  // Update Rust crates
  console.log('Updating Rust Cargo.toml files...');
  const cargoFiles = findCargoFiles();
  let updatedCount = 0;

  for (const cargoFile of cargoFiles) {
    if (updateCargoToml(cargoFile, version)) {
      console.log(`  Updated: ${cargoFile}`);
      updatedCount++;
    }
  }

  console.log(`  ${updatedCount} Cargo.toml files updated`);
  console.log();

  // Update Android
  console.log('Updating Android version...');
  updateAndroidVersion(version);
  console.log();

  // Update iOS
  console.log('Updating iOS version...');
  updateIOSVersion(version);
  console.log();

  console.log('='.repeat(50));
  console.log('Version sync complete!');
  console.log();
  console.log('Next steps:');
  console.log('  1. Review changes: git diff');
  console.log('  2. Commit: git add -A && git commit -m "chore: version packages"');
  console.log('  3. Tag: git tag -a v' + version + ' -m "Release v' + version + '"');
}

main();
