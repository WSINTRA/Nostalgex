// Seasonal bundles for the web tuner: when one is in season, which one the invite
// above channel one offers, which channels lead the guide, and what the invite and
// the Settings row say.
//
// A seasonal bundle (`activeMonths` set) is never switched on for anyone and, once
// switched on, stays on in every month. Its season only decides the invite and the
// guide lead. `seasonStart` starts the season before the first of its first month:
// TIS THE SEASON is `activeMonths: [12]` with
// `seasonStart: { "relativeTo": "usThanksgiving", "days": -7 }`, so it is in season
// from local midnight a week before US Thanksgiving (the fourth Thursday of November)
// to the end of December. The early part runs from that day to the end of its month.
// An anchor this build does not know is ignored.
//
// PARITY with tvOS
//   Nostalgex/Nostalgex/Models/ChannelBundle.swift      SeasonStart, isInSeason, spotlightLabel
//   Nostalgex/Nostalgex/Models/SeasonalPrompt.swift     bundleToOffer, headline
//   Nostalgex/Nostalgex/Models/GuideChannelOrder.swift  seasonalLeadIDs
// Shared vectors: scripts/season-golden.json (NostalgexTests/SeasonGoldenTests.swift and
// `npm run test:season`). Dates are local, as on the device.
//
// USAGE (browser: plain <script src="scripts/nostalgex-season.js">,
// node: `import "./nostalgex-season.js"`, then globalThis):
//
//   const S = window.NostalgexSeason;
//   S.isInSeason(bundle, new Date());
//   S.bundleToOffer(bundles, enabledBundleIDs, new Date(), isSilenced);

(function (global) {
  'use strict';

  const US_THANKSGIVING = 'usThanksgiving';
  const MONTH_ABBR = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  function isSeasonal(bundle) {
    return !!bundle && Array.isArray(bundle.activeMonths);
  }

  /** Local midnight of US Thanksgiving, the fourth Thursday of November. */
  function usThanksgiving(year) {
    const november1 = new Date(year, 10, 1);
    const firstThursday = 1 + ((4 - november1.getDay() + 7) % 7);
    return new Date(year, 10, firstThursday + 21);
  }

  /** Local midnight of `seasonStart` in `year`, or null (none, or an unknown anchor). */
  function seasonStartDate(bundle, year) {
    if (!isSeasonal(bundle)) return null;
    const start = bundle.seasonStart;
    if (!start || start.relativeTo !== US_THANKSGIVING) return null;
    const days = Number.isInteger(start.days) ? start.days : 0;
    const anchor = usThanksgiving(year);
    return new Date(year, anchor.getMonth(), anchor.getDate() + days);
  }

  /** Mirrors ChannelBundle.isInSeason(on:). A bundle without activeMonths always is. */
  function isInSeason(bundle, now) {
    if (!isSeasonal(bundle)) return true;
    const month = now.getMonth() + 1;
    if (bundle.activeMonths.includes(month)) {
      // Late September gate: if September is in the list, only from the 15th onward.
      return month !== 9 || now.getDate() >= 15;
    }
    // A season that starts early: from `seasonStart` to the end of that month.
    const start = seasonStartDate(bundle, now.getFullYear());
    return !!start && now >= start && now.getMonth() === start.getMonth();
  }

  /** Mirrors SeasonalPrompt.bundleToOffer: the first seasonal bundle in season, off and not silenced. */
  function bundleToOffer(bundles, enabledBundleIDs, now, isSilenced) {
    return (bundles || []).find((b) => isSeasonal(b) && isInSeason(b, now)
      && !enabledBundleIDs.has(b.id) && !isSilenced(b.id)) || null;
  }

  /** Mirrors GuideChannelOrder.seasonalLeadIDs: channels of every seasonal bundle on and in season. */
  function seasonalLeadIDs(bundles, enabledBundleIDs, now) {
    return (bundles || [])
      .filter((b) => isSeasonal(b) && enabledBundleIDs.has(b.id) && isInSeason(b, now))
      .flatMap((b) => b.channelIDs || []);
  }

  /** Mirrors SeasonalPrompt.headline. TIS THE SEASON only says December in December. */
  function inviteHeadline(bundle, now) {
    if (bundle.id === 'seasonal') return "IT'S OCTOBER. ARE YOU READY TO SCREAM?";
    if (bundle.id === 'tis-the-season') {
      return now.getMonth() === 11 ? "IT'S DECEMBER. DECK THE CHANNELS." : 'THE HOLIDAYS ARE HERE. DECK THE CHANNELS.';
    }
    return `${bundle.name} IS IN SEASON.`;
  }

  /**
   * The Settings row note for a seasonal bundle outside its season, mirroring
   * ChannelBundle.spotlightLabel: "SPOTLIGHTED OCT", or "SPOTLIGHTED NOV 19 TO DEC 31"
   * for one with `seasonStart` (this year's dates, which outside the season are the
   * next ones). Empty for a bundle without activeMonths. It replaced "(OFF SEASON)",
   * which read as "switched off" when the bundle works in every month.
   */
  function seasonalSpotlightLabel(bundle, now) {
    const months = isSeasonal(bundle) ? bundle.activeMonths : null;
    if (!months || months.length === 0) return '';
    const start = seasonStartDate(bundle, now.getFullYear());
    const last = months[months.length - 1];
    if (start && MONTH_ABBR[last - 1]) {
      const endYear = last < start.getMonth() + 1 ? start.getFullYear() + 1 : start.getFullYear();
      const lastDay = new Date(endYear, last, 0).getDate();
      return `SPOTLIGHTED ${MONTH_ABBR[start.getMonth()]} ${start.getDate()} TO ${MONTH_ABBR[last - 1]} ${lastDay}`;
    }
    const names = months.map((m) => MONTH_ABBR[m - 1]).filter(Boolean);
    return names.length ? `SPOTLIGHTED ${names.join(', ')}` : '';
  }

  const api = {
    US_THANKSGIVING, usThanksgiving, seasonStartDate, isInSeason, bundleToOffer,
    seasonalLeadIDs, inviteHeadline, seasonalSpotlightLabel,
  };

  global.NostalgexSeason = api;
  if (typeof module !== 'undefined' && typeof module.exports !== 'undefined') {
    module.exports = api;
  }
})(typeof window !== 'undefined' ? window : globalThis);
