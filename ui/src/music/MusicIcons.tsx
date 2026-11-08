import type {ReactNode, SVGProps} from 'react';

export const drumIconNames = ['kick', 'snare', 'clap', 'closed-hat', 'open-hat', 'low-tom', 'high-tom', 'bell'] as const;
export type DrumIconName = typeof drumIconNames[number];
export type MusicIconProps = Omit<SVGProps<SVGSVGElement>, 'children' | 'name'> & {size?: number; title?: string};
const shapes: Record<DrumIconName, ReactNode> = {
  "kick": <><path d="M27 11C17 11 10 20 10 32S17 53 27 53H35V11Z" fill="currentColor" fillOpacity=".10" stroke="none"/>
<path d="M27 11C17 11 10 20 10 32S17 53 27 53M15 18L24 18M11 29H20M14 45L23 45" opacity=".55"/>
<ellipse cx="35" cy="32" rx="19" ry="22" fill="currentColor" fillOpacity=".045"/>
<ellipse cx="35" cy="32" rx="15" ry="18"/>
<path d="M28 13V17M42 13V17M18 27H22M48 27H52M20 44L24 42M46 43L50 46M29 48V52M41 48V52"/>
<circle cx="40" cy="38" r="4.5" fill="currentColor" fillOpacity=".16"/>
<path d="M16 48L11 58H17M49 49L54 58H48M32 51L29 59H39L36 51M33 43V53"/>
<circle cx="33" cy="42" r="2.5" fill="currentColor"/></>,
  "snare": <><path d="M10 24V41C10 48 54 48 54 41V24" fill="currentColor" fillOpacity=".12"/>
<ellipse cx="32" cy="24" rx="22" ry="9" fill="currentColor" fillOpacity=".05"/>
<ellipse cx="32" cy="24" rx="17.5" ry="5.5" opacity=".65"/>
<path d="M10 39C12 50 52 50 54 39M10 34C14 44 50 44 54 34" opacity=".6"/>
<path d="M15 29V40M25 32V44M39 32V44M49 29V40M13 31H17M23 34H27M37 34H41M47 31H51"/>
<path d="M22 48L41 53M25 46L44 51M19 50L38 55" opacity=".65"/>
<path d="M17 13L43 7M22 8L48 15" strokeWidth="2.3"/>
<circle cx="16" cy="13" r="1.5" fill="currentColor"/><circle cx="49" cy="15" r="1.5" fill="currentColor"/></>,
  "clap": <><path d="M14 53L9 45C7 41 8 37 10 34L17 23C19 20 22 22 21 25L17 33L30 14C32 11 35 13 33 16L24 30L37 14C39 12 42 15 40 18L29 33L41 20C44 17 47 20 44 23L33 37L42 30C45 28 48 31 45 34L32 47C28 51 25 54 22 57Z" fill="currentColor" fillOpacity=".08"/>
<path d="M33 54L27 48C24 45 25 41 27 38L37 27C39 25 42 27 40 30L34 38L47 26C50 23 53 26 50 29L41 39L51 32C54 30 57 33 54 36L43 45C40 48 39 52 39 56Z" fill="currentColor" fillOpacity=".17"/>
<path d="M15 45L23 38M33 47L38 43" opacity=".55"/>
<path d="M12 18L8 14M20 12L19 6M47 12L51 7M53 20L59 18" strokeWidth="1.9"/></>,
  "closed-hat": <><path d="M32 10V52M28 52H36M32 51L21 58M32 51L44 58"/>
<path d="M9 29C15 24 23 25 28 22Q32 18 36 22C41 25 49 24 55 29C42 34 22 34 9 29Z" fill="currentColor" fillOpacity=".12"/>
<path d="M9 33Q32 40 55 33M11 30L9 33M53 30L55 33" fill="currentColor" fillOpacity=".05"/>
<path d="M17 29Q32 33 47 29M26 26Q32 28 38 26" opacity=".45"/>
<ellipse cx="32" cy="21" rx="4" ry="2" fill="currentColor" fillOpacity=".18"/>
<path d="M29 12H35M30 16H34M41 55L48 54L51 58H44"/></>,
  "open-hat": <><path d="M32 8V52M28 52H36M32 51L21 58M32 51L44 58"/>
<path d="M9 23C16 18 24 19 28 16Q32 12 36 16C40 19 48 18 55 23Q32 30 9 23Z" fill="currentColor" fillOpacity=".12"/>
<path d="M9 37Q32 31 55 37Q32 44 9 37Z" fill="currentColor" fillOpacity=".10"/>
<path d="M16 23Q32 27 48 23M17 37Q32 40 47 37" opacity=".45"/>
<ellipse cx="32" cy="15" rx="4" ry="2" fill="currentColor" fillOpacity=".18"/>
<path d="M29 9H35M58 26V33M56 28L58 26L60 28M56 31L58 33L60 31M41 55L48 54L51 58"/></>,
  "low-tom": <><path d="M11 23L14 45C15 53 49 53 50 45L53 23" fill="currentColor" fillOpacity=".12"/>
<ellipse cx="32" cy="23" rx="21" ry="10" fill="currentColor" fillOpacity=".04"/>
<ellipse cx="32" cy="23" rx="16" ry="6.5" opacity=".65"/>
<path d="M16 41C18 49 46 49 48 41M17 30L19 43M27 33V47M39 33V47M48 30L46 43M15 31H20M25 35H29M37 35H41M44 31H49"/>
<path d="M16 47L12 58M48 47L52 58M32 51V60M10 58H15M49 58H54"/>
<path d="M20 22Q31 17 43 22" opacity=".35"/></>,
  "high-tom": <><path d="M17 20L20 41C21 47 43 47 44 41L47 20" fill="currentColor" fillOpacity=".12"/>
<ellipse cx="32" cy="20" rx="15" ry="8" fill="currentColor" fillOpacity=".04"/>
<ellipse cx="32" cy="20" rx="11" ry="5" opacity=".65"/>
<path d="M21 37Q32 46 43 37M21 26L23 39M30 29V43M40 27L39 40M19 28H24M28 31H32M37 29H42"/>
<path d="M44 30H52V48H40M40 46V57M39 53L30 59M41 53L50 59"/>
<rect x="38" y="45" width="5" height="7" rx="1" fill="currentColor" fillOpacity=".22"/>
<path d="M24 19Q31 15 39 19" opacity=".35"/></>,
  "bell": <><path d="M20 45C24 39 24 28 25 22C26 17 39 17 40 22C41 28 41 39 45 45Z" fill="currentColor" fillOpacity=".12"/>
<ellipse cx="32.5" cy="45" rx="17.5" ry="6.5" fill="currentColor" fillOpacity=".08"/>
<ellipse cx="32.5" cy="45" rx="12" ry="3.5" opacity=".55"/>
<path d="M29 18V12Q32.5 7 36 12V18M29 26L27 37M32 47V53"/>
<circle cx="32" cy="54" r="3" fill="currentColor" fillOpacity=".2"/>
<path d="M12 25L7 22M13 34H6M49 25L54 20M52 34L59 32" strokeWidth="1.9"/></>,
};

/** Original grayscale percussion glyphs. No filters, images, or audio waveforms. */
export function DrumIcon({name, size=56, title, ...props}: MusicIconProps & {name: DrumIconName}) {
  return <svg width={size} height={size} viewBox="0 0 64 64" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" focusable="false" aria-hidden={title ? undefined : true} role={title ? 'img' : undefined} aria-label={title} data-music-icon={name} {...props}>
    {title && <title>{title}</title>}{shapes[name]}
  </svg>;
}
export function KickIcon(props: MusicIconProps) {return <DrumIcon name="kick" {...props}/>;}
export function SnareIcon(props: MusicIconProps) {return <DrumIcon name="snare" {...props}/>;}
export function ClapIcon(props: MusicIconProps) {return <DrumIcon name="clap" {...props}/>;}
export function ClosedHatIcon(props: MusicIconProps) {return <DrumIcon name="closed-hat" {...props}/>;}
export function OpenHatIcon(props: MusicIconProps) {return <DrumIcon name="open-hat" {...props}/>;}
export function LowTomIcon(props: MusicIconProps) {return <DrumIcon name="low-tom" {...props}/>;}
export function HighTomIcon(props: MusicIconProps) {return <DrumIcon name="high-tom" {...props}/>;}
export function BellIcon(props: MusicIconProps) {return <DrumIcon name="bell" {...props}/>;}
