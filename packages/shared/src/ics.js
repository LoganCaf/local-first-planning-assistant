/**
 * Minimal ICS parser for Canvas assignment feeds.
 * Extracts VEVENT blocks into a normalized shape the server can use.
 *
 * Returned assignment fields:
 * - title
 * - description
 * - location
 * - course (best-effort from summary suffix in brackets)
 * - url
 * - due (Date)
 * - end (Date|null)
 * - allDay (boolean)
 */
export function parseICSAssignments(icsText = '') {
  if (typeof icsText !== 'string' || !icsText.trim()) return [];

  // Unfold lines (RFC 5545: lines starting with space/tab are continuations)
  const unfolded = icsText
    .split(/\r?\n/)
    .reduce((acc, line) => {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        acc[acc.length - 1] = `${acc[acc.length - 1]}${line.slice(1)}`;
      } else {
        acc.push(line);
      }
      return acc;
    }, [])
    .join('\n');

  const events = unfolded.split('BEGIN:VEVENT').slice(1);
  return events
    .map((block) => block.split('END:VEVENT')[0])
    .map((block) => parseEventBlock(block))
    .filter(Boolean);
}

function parseEventBlock(block) {
  const fields = {};
  block
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .forEach((line) => {
      const [rawKey, ...rest] = line.split(':');
      if (!rawKey || rest.length === 0) return;
      const value = rest.join(':');
      const key = rawKey.split(';')[0].toUpperCase();
      fields[key] = value;
    });

  const title = fields.SUMMARY ? decodeText(fields.SUMMARY) : 'Untitled assignment';
  const description = fields.DESCRIPTION ? decodeText(fields.DESCRIPTION) : '';
  const location = fields.LOCATION ? decodeText(fields.LOCATION) : '';
  const url = fields.URL ? decodeText(fields.URL) : '';
  const uid = fields.UID ? decodeText(fields.UID) : undefined;

  const { start, end, allDay } = parseDates(fields.DTSTART, fields.DTEND);
  const course = extractCourseFromSummary(title);

  return {
    id: uid,
    title,
    description,
    location,
    url,
    course,
    due: start,
    end,
    allDay
  };
}

function parseDates(rawStart, rawEnd) {
  const start = parseDateValue(rawStart);
  const end = parseDateValue(rawEnd);
  const allDay = isAllDay(rawStart);

  if (!end && start && allDay) {
    const endOfDay = new Date(start);
    endOfDay.setHours(23, 59, 0, 0);
    return { start, end: endOfDay, allDay: true };
  }

  if (allDay && start) {
    const endOfDay = new Date(start);
    endOfDay.setHours(23, 59, 0, 0);
    return { start, end: endOfDay, allDay: true };
  }

  return { start, end: end ?? start, allDay };
}

function parseDateValue(value) {
  if (!value) return null;
  // Handle YYYYMMDD format (all-day)
  if (/^\d{8}$/.test(value)) {
    const year = Number(value.slice(0, 4));
    const month = Number(value.slice(4, 6)) - 1;
    const day = Number(value.slice(6, 8));
    // Use local noon to avoid timezone shifts when serialized (keeps same calendar day)
    return new Date(year, month, day, 12, 0, 0, 0);
  }

  // Handle datetime (with or without trailing Z) as "floating" local time to avoid date drift
  const localMatch = value.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$/i);
  if (localMatch) {
    const [, y, m, d, hh, mm, ss] = localMatch;
    return new Date(
      Number(y),
      Number(m) - 1,
      Number(d),
      Number(hh),
      Number(mm),
      Number(ss)
    );
  }

  // Fallback to native parsing for other formats
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isAllDay(value) {
  if (!value) return false;
  return /^\d{8}$/.test(value);
}

function decodeText(text) {
  return text.replace(/\\n/gi, '\n').replace(/\\,/g, ',').replace(/\\;/g, ';');
}

function extractCourseFromSummary(summary = '') {
  const bracketMatch = summary.match(/\[([^\]]+)\]$/);
  if (bracketMatch) return bracketMatch[1].trim();
  return '';
}
