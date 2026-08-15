import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const docsDir = join(root, "third-party/scriptable/Payload/Scriptable.app/docs");
const protoExtPath = join(
  root,
  "third-party/scriptable/Payload/Scriptable.app/Frameworks/ScriptableKit.framework/prototype-extensions.js",
);
const outPath = join(root, "docs/scriptable-api.json");
const testContractPath = join(
  root,
  "stupid-widgets/Tests/StupidWidgetsTests/GeneratedAPIContract.swift",
);

const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));

const index = readJson(join(docsDir, "index.json"));
const pagesById = new Map();
for (const f of readdirSync(docsDir).filter((f) => /^[0-9]\.json$/.test(f))) {
  const doc = readJson(join(docsDir, f));
  for (const det of doc.details) {
    pagesById.set(det.id, det);
    for (const section of det.detailsSections ?? []) {
      for (const member of section.details ?? []) pagesById.set(member.id, member);
    }
  }
}

const protoSrc = readFileSync(protoExtPath, "utf8");
const runtimeKeys = new Map();
const keyRe = /(\w+)\.prototype\._scriptable_keys=function\(\)\{return\[([^\]]*)\]\}/g;
for (const m of protoSrc.matchAll(keyRe)) {
  const members = m[2]
    .split(",")
    .map((s) => s.trim().replace(/^"|"$/g, ""))
    .filter((s) => s.length > 0);
  runtimeKeys.set(m[1], members);
}

function normalizeMember(m) {
  return {
    name: m.shortName ?? m.longName ?? m.copyDecleration ?? null,
    signature: m.decleration ?? m.longName ?? null,
    summary: m.summary ?? null,
    description: m.description ?? null,
    url: m.url ?? null,
    ...(m.subtitle ? { type: m.subtitle } : {}),
    ...(m.infoSections
      ? {
          parameters: m.infoSections.flatMap((s) =>
            (s.infos ?? []).map((i) => ({
              name: i.title ?? null,
              type: i.subtitle ?? null,
              description: i.description ?? null,
            })),
          ),
        }
      : {}),
    ...(m.returnValueDescription ? { returns: m.returnValueDescription } : {}),
  };
}

function buildType(det) {
  const props = [];
  const methods = [];
  for (const section of det.detailsSections ?? []) {
    const target = section.title === "Properties" ? props : methods;
    for (const m of section.details ?? []) target.push(normalizeMember(m));
  }
  const constructors = methods.filter((m) => typeof m.name === "string" && /^new\b/.test(m.name));
  const regularMethods = methods.filter((m) => !constructors.includes(m));
  return {
    kind: "type",
    name: det.longName ?? det.shortName ?? det.copyDecleration ?? null,
    summary: det.summary ?? null,
    description: det.description ?? null,
    url: det.url ?? null,
    constructors,
    properties: props,
    methods: regularMethods,
    runtimeMembers: runtimeKeys.get(det.shortName) ?? null,
  };
}

const types = {};
const globals = {};
const functions = {};
const pages = [];

for (const entry of index) {
  const det = pagesById.get(entry.pageEntryId);
  if (!det) continue;
  pages.push({
    pageEntryId: entry.pageEntryId,
    title: entry.title,
    summary: entry.summary,
    url: det.url ?? null,
  });
  const headline = det.headline;
  if (headline === "Type") {
    const t = buildType(det);
    if (t.name) types[t.name] = t;
  } else if (headline === "Global variable") {
    globals[det.longName ?? det.shortName] = normalizeMember(det);
  } else if (headline === "Function") {
    functions[det.longName ?? det.shortName] = normalizeMember(det);
  }
}

const spec = {
  source: { name: "Scriptable", bundleId: "dk.simonbs.Scriptable", version: "1.7.19" },
  generatedFrom: "docs/*.json + ScriptableKit.framework/prototype-extensions.js",
  types,
  globals,
  functions,
  pages,
};

writeFileSync(outPath, JSON.stringify(spec, null, 2));

const swiftArray = (values) => `[${values.map((value) => JSON.stringify(value)).join(", ")}]`;
const generatedTypes = Object.values(types)
  .sort((a, b) => a.name.localeCompare(b.name))
  .map((type) => {
    const instanceMethods = [];
    const asyncInstanceMethods = [];
    const staticMethods = [];
    const asyncStaticMethods = [];
    for (const method of type.methods) {
      if (!method.name || !type.runtimeMembers?.includes(method.name)) continue;
      const isStatic = method.signature?.startsWith("static ") ?? false;
      const isAsync = method.signature?.includes("Promise") ?? false;
      const target = isStatic
        ? isAsync
          ? asyncStaticMethods
          : staticMethods
        : isAsync
          ? asyncInstanceMethods
          : instanceMethods;
      target.push(method.name);
    }
    const instanceProperties = type.properties
      .map((property) => property.name)
      .filter((name) => name && type.runtimeMembers?.includes(name));
    return `    ${JSON.stringify(type.name)}: GeneratedAPITypeContract(
        instanceProperties: ${swiftArray(instanceProperties)},
        instanceMethods: ${swiftArray(instanceMethods)},
        asyncInstanceMethods: ${swiftArray(asyncInstanceMethods)},
        staticMethods: ${swiftArray(staticMethods)},
        asyncStaticMethods: ${swiftArray(asyncStaticMethods)},
        runtimeMembers: ${swiftArray(type.runtimeMembers ?? [])}
    )`;
  });

const testContract = `// Generated by tools/generate-api-spec.mjs. Do not edit.

struct GeneratedAPITypeContract {
    let instanceProperties: [String]
    let instanceMethods: [String]
    let asyncInstanceMethods: [String]
    let staticMethods: [String]
    let asyncStaticMethods: [String]
    let runtimeMembers: [String]
}

let generatedAPIContract: [String: GeneratedAPITypeContract] = [
${generatedTypes.join(",\n")}
]
`;

writeFileSync(testContractPath, testContract);
console.log("wrote", outPath);
console.log("wrote", testContractPath);
console.log("types:", Object.keys(types).length);
console.log("globals:", Object.keys(globals).length);
console.log("functions:", Object.keys(functions).length);
console.log("pages:", pages.length);

let totalMembers = 0;
let withRuntime = 0;
for (const t of Object.values(types)) {
  totalMembers += t.properties.length + t.methods.length + t.constructors.length;
  if (t.runtimeMembers) withRuntime++;
}
console.log("documented members:", totalMembers);
console.log("types with runtime member lists:", withRuntime, "/", Object.keys(types).length);
