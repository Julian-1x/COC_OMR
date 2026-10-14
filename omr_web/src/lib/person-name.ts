const LOWER_PARTICLES = new Set([
  "de",
  "del",
  "la",
  "las",
  "los",
  "van",
  "von",
  "y",
  "e",
  "da",
  "dos",
  "das",
  "san",
  "santa",
  "sta",
  "sto",
]);

/** Normalize teacher/student names to "First Last" title case. */
export function normalizePersonName(input: string): string {
  let value = input.trim().replace(/\s+/g, " ");
  if (!value) {
    return "";
  }

  if (value.includes(",")) {
    const parts = value
      .split(",")
      .map((part) => part.trim())
      .filter(Boolean);
    if (parts.length >= 2) {
      const family = parts.shift() ?? "";
      const given = parts.join(" ");
      value = `${given} ${family}`.trim().replace(/\s+/g, " ");
    }
  }

  const words = value.split(" ");
  const normalized: string[] = [];

  for (let index = 0; index < words.length; index += 1) {
    const word = words[index];
    if (!word) {
      continue;
    }

    const lower = word.toLowerCase();
    if (index > 0 && LOWER_PARTICLES.has(lower)) {
      normalized.push(lower);
      continue;
    }

    if (
      index > 0 &&
      lower === "de" &&
      index + 1 < words.length &&
      ["la", "los", "las"].includes(words[index + 1].toLowerCase())
    ) {
      normalized.push("de", words[index + 1].toLowerCase());
      index += 1;
      continue;
    }

    normalized.push(titleWord(word));
  }

  return normalized.join(" ");
}

const SURNAME_PARTICLES = new Set([
  "de",
  "del",
  "dela",
  "la",
  "las",
  "los",
  "van",
  "von",
  "da",
  "dos",
  "das",
  "san",
  "santa",
  "sta",
  "sto",
]);

const NAME_SUFFIX = /^(jr|sr|ii|iii|iv)\.?$/i;

/** Sort key is the surname (last word, plus particles such as "de los"). */
export function surnameSortKey(name: string): string {
  const words = name.trim().replace(/\s+/g, " ").split(" ").filter(Boolean);
  while (words.length > 1 && NAME_SUFFIX.test(words[words.length - 1])) {
    words.pop();
  }
  if (words.length === 0) return "";
  let start = words.length - 1;
  while (start > 0 && SURNAME_PARTICLES.has(words[start - 1].toLowerCase())) {
    start -= 1;
  }
  return words.slice(start).join(" ").toLowerCase();
}

export function compareByLastName(a: string, b: string): number {
  const byLast = surnameSortKey(a).localeCompare(surnameSortKey(b), "en", {
    sensitivity: "base",
  });
  if (byLast !== 0) return byLast;
  return a.localeCompare(b, "en", { sensitivity: "base" });
}

/** Combine separate fields (form: last name, then first name) into stored "First Last" form. */
export function normalizePersonNameFromParts(
  firstName: string,
  lastName: string,
  suffix?: string,
): string {
  const given = firstName.trim();
  const family = lastName.trim();
  if (!given || !family) {
    return "";
  }
  let combined = `${given} ${family}`;
  const extra = suffix?.trim() ?? "";
  if (extra) {
    combined = `${combined} ${extra}`;
  }
  return normalizePersonName(combined);
}

function titleWord(word: string): string {
  if (!word) {
    return word;
  }

  if (word.includes("-")) {
    return word.split("-").map(titleWord).join("-");
  }

  const apostrophe = word.indexOf("'");
  if (apostrophe >= 0 && apostrophe < word.length - 1) {
    return `${word.slice(0, apostrophe + 1)}${titleWord(word.slice(apostrophe + 1))}`;
  }

  const lower = word.toLowerCase();
  if (lower.startsWith("mc") && lower.length > 2) {
    return `Mc${titleWord(word.slice(2))}`;
  }

  if (/^(jr|sr|ii|iii|iv)\.?$/i.test(lower)) {
    const suffix = lower.endsWith(".") ? "." : "";
    return `${lower.replace(".", "").toUpperCase()}${suffix}`;
  }

  return lower.charAt(0).toUpperCase() + lower.slice(1);
}
