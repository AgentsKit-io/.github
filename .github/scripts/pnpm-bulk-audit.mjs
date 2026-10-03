#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { createRequire } from 'node:module'

const severityRank = new Map([
  ['info', 0],
  ['low', 1],
  ['moderate', 2],
  ['high', 3],
  ['critical', 4],
])
const level = (process.env.AUDIT_LEVEL || 'high').toLowerCase()
const threshold = severityRank.get(level)
if (threshold === undefined) {
  throw new Error(`Unsupported AUDIT_LEVEL: ${level}`)
}

const productionOnly = process.env.PRODUCTION_ONLY === 'true'
const args = ['list', '-r', ...(productionOnly ? ['--prod'] : []), '--json', '--depth', 'Infinity']
const projects = JSON.parse(execFileSync('pnpm', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }) || '[]')
const versionsByName = new Map()

function collect(dependencies) {
  if (!dependencies || typeof dependencies !== 'object') return
  for (const [name, info] of Object.entries(dependencies)) {
    if (!info || typeof info !== 'object') continue
    const version = info.version
    if (typeof version === 'string' && version && !version.startsWith('link:') && !version.startsWith('workspace:')) {
      if (!versionsByName.has(name)) versionsByName.set(name, new Set())
      versionsByName.get(name).add(version)
    }
    collect(info.dependencies)
  }
}

for (const project of Array.isArray(projects) ? projects : [projects]) {
  collect(project.dependencies)
}
if (versionsByName.size === 0) {
  throw new Error('No dependencies found in the pnpm dependency graph')
}

const dependencyVersions = Object.fromEntries(
  [...versionsByName].map(([name, versions]) => [name, [...versions].sort()]),
)
const response = await fetch('https://registry.npmjs.org/-/npm/v1/security/advisories/bulk', {
  method: 'POST',
  headers: {
    accept: 'application/json',
    'content-type': 'application/json',
    'user-agent': 'agentskit-pnpm-bulk-audit',
  },
  body: JSON.stringify(dependencyVersions),
})
if (!response.ok) {
  throw new Error(`Bulk advisory endpoint HTTP ${response.status}: ${(await response.text()).slice(0, 500)}`)
}

const advisoriesByPackage = await response.json()
let semver
try {
  semver = createRequire(`${process.cwd()}/package.json`)('semver')
} catch {
  semver = { satisfies: (version, range) => range === version || range === `=${version}` }
}

const findings = []
for (const [name, versions] of Object.entries(dependencyVersions)) {
  for (const version of versions) {
    for (const advisory of advisoriesByPackage[name] ?? []) {
      const severity = String(advisory.severity ?? '').toLowerCase()
      const vulnerableRange = advisory.vulnerable_versions ?? advisory.vulnerableVersionRange
      if (
        severityRank.has(severity) && severityRank.get(severity) >= threshold &&
        typeof vulnerableRange === 'string' &&
        semver.satisfies(version, vulnerableRange, { includePrerelease: true })
      ) {
        findings.push({ name, version, severity, title: advisory.title ?? 'unknown', url: advisory.url ?? '' })
      }
    }
  }
}

if (findings.length) {
  for (const finding of findings) {
    process.stderr.write(`${finding.severity}: ${finding.name}@${finding.version}: ${finding.title} ${finding.url}\n`)
  }
  process.exitCode = 1
} else {
  process.stdout.write(`No ${level}+ advisories found across ${versionsByName.size} packages.\n`)
}
