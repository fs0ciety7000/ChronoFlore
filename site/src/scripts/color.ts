/** Linear mix of two `#rrggbb` colors; `t` is clamped to [0, 1]. */
export function mixHex(a: string, b: string, t: number): string {
  const k = Number.isFinite(t) ? Math.min(1, Math.max(0, t)) : 0;
  const out = [1, 3, 5].map((i) => {
    const x = parseInt(a.slice(i, i + 2), 16);
    const y = parseInt(b.slice(i, i + 2), 16);
    return Math.round(x + (y - x) * k)
      .toString(16)
      .padStart(2, '0');
  });
  return `#${out.join('')}`;
}

/** WCAG relative luminance of a `#rrggbb` color. */
export function luminance(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG contrast ratio between two `#rrggbb` colors. */
export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}
