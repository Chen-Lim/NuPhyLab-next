import type { ReactNode, SVGProps } from 'react';

export const drumIconNames = [
  'kick', 'snare', 'clap', 'closed-hat', 'open-hat', 'low-tom', 'high-tom', 'bell',
] as const;

export type DrumIconName = typeof drumIconNames[number];

type GraphicProps = Omit<SVGProps<SVGSVGElement>, 'children' | 'name' | 'title'> & {
  size?: number;
  title?: string;
};

// Filled points suggest the sound's envelope, spacing, or register.
const drumPatterns: Record<DrumIconName, readonly string[]> = {
  kick: [
    '..###..',
    '.##.##.',
    '##...##',
    '#..#..#',
    '##...##',
    '.##.##.',
    '..###..',
  ],
  snare: [
    '...#...',
    '.#.#.#.',
    '..###..',
    '#######',
    '..###..',
    '.#.#.#.',
    '...#...',
  ],
  clap: [
    '...#..#',
    '..#..#.',
    '.#..#..',
    '#..#...',
    '.#..#..',
    '..#..#.',
    '...#..#',
  ],
  'closed-hat': [
    '.......',
    '.......',
    '...#...',
    '#######',
    '...#...',
    '.......',
    '.......',
  ],
  'open-hat': [
    '.......',
    '#######',
    '.#...#.',
    '..#.#..',
    '.#...#.',
    '#######',
    '.......',
  ],
  'low-tom': [
    '.......',
    '.......',
    '.......',
    '##.....',
    '####...',
    '######.',
    '#######',
  ],
  'high-tom': [
    '#######',
    '.######',
    '...####',
    '.....##',
    '.......',
    '.......',
    '.......',
  ],
  bell: [
    '...#...',
    '..#.#..',
    '.#...#.',
    '#..#..#',
    '.#...#.',
    '..#.#..',
    '...#...',
  ],
};

export function DrumIcon({ name, size = 48, title, ...props }: GraphicProps & { name: DrumIconName }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 48 48"
      fill="currentColor"
      focusable="false"
      aria-hidden={title ? undefined : true}
      role={title ? 'img' : undefined}
      aria-label={title}
      data-music-icon={name}
      {...props}
    >
      {title && <title>{title}</title>}
      {drumPatterns[name].map((row, y) => Array.from(row, (point, x) => (
        <circle
          key={`${x}-${y}`}
          cx={6 + x * 6}
          cy={6 + y * 6}
          r={point === '#' ? 1.95 : 1.15}
          opacity={point === '#' ? 1 : 0.20}
        />
      )))}
    </svg>
  );
}

export const presetCoverGenres = ['boombap', 'trap', 'rock', 'lofi', 'funk', 'ambient'] as const;
export type PresetCoverGenre = typeof presetCoverGenres[number] | 'original';

const coverMarks: Record<PresetCoverGenre, ReactNode> = {
  boombap: (
    <>
      <path d="M12 12h16v8H12zM36 12h8v8h-8zM60 12h24v8H60zM20 23h16v8H20zM44 23h16v8H44zM68 23h8v8h-8zM12 34h24v8H12zM44 34h8v8h-8zM68 34h16v8H68z" />
    </>
  ),
  trap: (
    <>
      <path d="M11 41 36 11h10L21 41zM29 41l25-30h7L36 41zM44 41l25-30h4L48 41zM55 41l25-30h2L57 41zM64 41l20-24v4L67 41zM73 41l11-13v4l-8 9z" />
      <path d="M11 11h16v2H11zM80 39h4v2h-4z" opacity=".45" />
    </>
  ),
  rock: (
    <>
      <path d="M9 32h11l9-16 7 9 10-16 9 18 8-12 8 17h16v4H68l-6-12-8 12-9-19-9 16-7-9-6 12H9z" />
      <path d="M9 41h78v2H9z" opacity=".45" />
    </>
  ),
  lofi: (
    <>
      <path d="M11 14h29v4H11zM48 14h36v4H48zM17 22h31v4H17zM56 22h22v4H56zM11 30h19v4H11zM38 30h34v4H38zM24 38h27v3H24zM58 38h26v3H58z" />
      <path d="M11 22h3v4h-3zM32 30h3v4h-3zM52 38h3v3h-3zM80 22h4v4h-4z" opacity=".35" />
    </>
  ),
  funk: (
    <>
      <path d="M14 34h7v8h-7zM25 20h7v22h-7zM36 27h7v15h-7zM47 10h7v32h-7zM58 31h7v11h-7zM69 16h7v26h-7zM80 25h7v17h-7z" />
      <path d="M14 28h7v2h-7zM36 21h7v2h-7zM58 25h7v2h-7zM80 19h7v2h-7z" opacity=".45" />
    </>
  ),
  ambient: (
    <>
      <ellipse cx="48" cy="26" rx="34" ry="12" fill="none" stroke="currentColor" strokeWidth="1.7" transform="rotate(-15 48 26)" />
      <ellipse cx="48" cy="26" rx="25" ry="9" fill="none" stroke="currentColor" strokeWidth="1.5" opacity=".42" transform="rotate(14 48 26)" />
      <circle cx="48" cy="26" r="4.5" />
      <circle cx="75" cy="13" r="3.1" />
      <circle cx="20" cy="37" r="2.4" />
    </>
  ),
  original: (
    <path d="M11 24h4v4h-4zM18 21h4v10h-4zM25 16h4v20h-4zM32 12h4v28h-4zM39 18h4v16h-4zM46 22h4v8h-4zM53 15h4v22h-4zM60 19h4v14h-4zM67 13h4v26h-4zM74 20h4v12h-4zM81 24h4v4h-4z" />
  ),
};

export function PresetCover({ genre, size = 96, title, ...props }: GraphicProps & { genre: PresetCoverGenre }) {
  return (
    <svg
      width={size}
      height={size * 52 / 96}
      viewBox="0 0 96 52"
      fill="currentColor"
      focusable="false"
      aria-hidden={title ? undefined : true}
      role={title ? 'img' : undefined}
      aria-label={title}
      data-music-cover={genre}
      {...props}
    >
      {title && <title>{title}</title>}
      {coverMarks[genre]}
    </svg>
  );
}
