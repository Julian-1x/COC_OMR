/** Read a fetch Response as JSON without throwing on HTML/plain-text bodies. */
export async function readJsonResponse<T extends Record<string, unknown>>(
  response: Response,
): Promise<T> {
  const text = await response.text();
  if (!text.trim()) {
    return {} as T;
  }

  try {
    return JSON.parse(text) as T;
  } catch {
    throw new Error(friendlyNonJsonBody(text, response.status));
  }
}

function friendlyNonJsonBody(text: string, status: number): string {
  const snippet = text.replace(/\s+/g, " ").trim().slice(0, 80).toLowerCase();
  if (
    snippet.startsWith("an error") ||
    snippet.includes("bad gateway") ||
    snippet.includes("gateway time") ||
    status === 502 ||
    status === 504
  ) {
    return "School server is not responding. Confirm the API is running, then try again in a minute.";
  }
  if (status >= 500) {
    return "School server error. Try again in a minute.";
  }
  return "Unexpected response from the school server. Refresh the page and try again.";
}
