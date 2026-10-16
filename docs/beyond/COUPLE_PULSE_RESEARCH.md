# Couple Pulse and "grow together" couples apps: research notes

Exploratory product research for **Bond Touch Beyond**. The question: what do couples apps
that have something "grow" between partners actually do, and what do reviewers like and
dislike about it? It feeds [GROW_TOGETHER_CONCEPTS.md](GROW_TOGETHER_CONCEPTS.md).

- Researched 2026-10-16 from public pages only: App Store listings (fetched through Apple's
  public iTunes lookup / customer-review RSS endpoints), developer sites, press and review
  write-ups. No app was installed and no account was created.
- Mechanics are described in our own words. No names, art, copy or other proprietary
  material from these apps should be reused in Bond Touch Beyond.
- Ratings and prices are what the US storefront showed on that date. They change often.

---

## 1. Couple Pulse

### Which app this is

Several unrelated iOS apps have "Pulse" in the name, including a couples check-in app, a
couples-questions app, and a Vienna startup that reads Apple Watch health data [S2]. The
one actually titled **"Couple Pulse: Relationship app"** is by Couple Space Inc. (App Store
id 6757607240) [S1][S3]:

| | |
|---|---|
| First release | 2026-02-09 |
| Version on 2026-10-16 | 1.36 (2026-09-24) |
| Rating | 4.75 from 12 ratings (US). Very little review data. |
| Age rating | 16+/17+ (mild suggestive themes, from the question packs) |
| Genre | Lifestyle, iOS 17.6+ |

### Core loop

Couple Pulse has **nothing that grows**. Its listing and website describe a private shared
space for two, built around "Ask / Play / Feel" [S1][S3]:

1. **Daily question.** Both partners answer the same prompt. Each partner's answer stays
   hidden until both have answered, then the two are shown side by side. The developer
   presents this "first shared action" as the onboarding win [S3].
2. **Play.** Quizzes, "who's more likely" style games, photo challenges and a shared
   drawing canvas [S1][S3].
3. **Feel (the "pulse").** The phone camera and flash read a fingertip pulse
   (photoplethysmography). Partners can save a recording that the other replays as phone
   haptics, or (Premium) share a heartbeat live. Live sessions are not saved. The app
   carries an "entertainment, not medical" disclaimer [S1][S3].
4. **Ambient presence.** Home and Lock Screen widgets show a relationship-day counter,
   distance and the shared drawing [S1][S3].
5. **Memories.** Saved answers, photos and heartbeat recordings with captions build up into
   a shared archive [S1][S3].

So the "something shared that accumulates" is an archive: answers, drawings and heartbeat
keepsakes. There is no pet or plant, and the public pages describe **no streak, decay or
points** system.

### How it is shared

There is one couple space per linked pair, and only two people are supported. Content
written there is visible to the partner. Unlinking disables sharing and deletes
couple-scoped content from the developer's active systems [S1]. Sync is on the developer's
servers, and accounts are needed to pair.

### Monetization

Freemium with a large set of subscription options [S1]:

- Free: pairing, daily questions, limited quizzes and check-ins, memories, drawing, a
  counter widget, and only the **latest** heartbeat recording per person.
- Premium: live heartbeat, full recording history, extra question packs, premium widget,
  stickers and drawing tools.
- **Couple sharing:** if one partner subscribes, both get the shared Premium features while
  they stay linked. This is a fair touch that reviewers of other apps ask for.
- Listed IAPs: weekly $5.99, monthly $8.99, yearly $24.99, a $39.99 tier, a $49.99
  "lifetime offer", and a $200.00 lifetime. A weekly tier next to a $200 lifetime looks like
  price anchoring.

### What reviewers say

There are too few reviews to treat this as a pattern [S4]:

- **Positive:** two reviews say the app made them feel closer than they expected, mainly
  because of time spent in the app at the same moment, and that the question themes
  surfaced topics they had not discussed. They also liked the design.
- **Negative:** one review says the widgets don't work and the app asks to pair when the
  couple is already paired.

### Relevance to Bond Touch Beyond

Couple Pulse overlaps a lot with what Beyond already has: heartbeat sharing (Beyond reads
the Apple Watch heart rate in `HeartView`), presence widgets, distance, and a relationship
counter (Beyond has the Encounters countdown). Neither app has a mechanic where the
partners' small daily gestures *accumulate into something alive*. That gap is what the
concept doc explores. The one Couple Pulse idea worth noting is the **hide-until-both-answer
reveal**: it rewards both partners showing up without punishing either one.

---

## 2. Comparable apps (brief)

### FurTwo (couples virtual pet) [S5][S6]

- **What grows:** one pet shared by the two partners. It has XP, levels and life stages, and
  six needs stats: hunger, happiness, energy, hygiene, health and discipline.
- **Feeding it:** the care actions are **split between partners**. One partner plays,
  trains and puts it to sleep. The other feeds, cleans and heals. Neither partner can keep
  it healthy alone. Daily prompts, couple challenges, a shared doodle canvas and mini-games
  sit around the pet.
- **Money:** weekly $7.99, monthly $9.99, yearly $59.99 (or $29.99 one-off for a year).
- **Reviews:** people like the nostalgic Tamagotchi feel ("but meaningful"). Complaints are
  about paying just to have fun together, a free tier that leaves "nothing to do", and
  pairing codes that fail.
- **Lesson:** forced interdependence is a strong hook, but needs-stats turn the partner
  into someone who is "letting the pet down".

### Widgetable (widgets plus co-parented pets) [S7][S8][S9]

- **What grows:** pets that friends or couples co-parent from home-screen widgets. Eggs
  hatch on timers, and the pets need food and baths bought with coins.
- **Decay:** pets that aren't fed can **run away or die**. One review describes released
  pets leaving a note that made the child reviewer cry and feel guilty, with money needed to
  bring them back.
- **Money:** Premium $4.99/month or $19.99/year, plus diamonds and eggs, plus heavy rewarded
  video ads [S8][S9].
- **Reviews (recent US):** people love how cute the widgets and pets are. The most common
  complaints are having to watch ads to feed pets (some ads reportedly loop for about two
  minutes), food that costs too much, long hatch timers, and pets that die when not fed
  ("feeding should be optional") [S9].
- **Lesson:** this is the clearest example of what to avoid. Neglect is punished, the guilt
  is emotional, and the fix is paid. Users ask for exactly the opposite.

### Finch (solo self-care pet) [S10][S11][S12]

- **What grows:** a small bird that grows up and goes on "adventures". Completing self-care
  goals gives it energy, and you earn currency for cosmetic items.
- **Decay:** none. Reviewers stress that the bird **never dies**, streaks don't punish you,
  and missing a day costs nothing [S11]. That no-guilt design is the main reason people
  praise it.
- **Money:** a generous free core with no ads. Plus (about $70/year) is mostly cosmetic
  [S11][S12].
- **Concerns:** one write-up cites a diary study where, over months, intrinsic motivation
  drifted toward chasing rewards. Others mention billing confusion [S11].
- **Lesson:** a growing companion works without punishment. Keep the rewards expressive
  rather than transactional.

### Forest (focus timer that grows trees) [S13][S14][S15]

- **What grows:** a tree for each focus session. Longer sessions grow bigger trees, and the
  trees fill a forest over time. Coins unlock species and can fund real-world tree planting
  with a partner NGO [S13].
- **Decay:** leaving the app mid-session **kills the tree**, and the dead tree stays in your
  forest unless you spend currency to remove it [S14][S15].
- **Money:** a paid app on iOS (a few dollars, once) [S15].
- **Lesson:** a forest made of your own history is very satisfying, and loss aversion
  works. But a dead tree on permanent display is a guilt artifact, and it would land much
  harder between two people than for one.

### Paired (couples questions with a streak) [S16][S17][S18]

- **What grows:** no creature. There is a daily question that both answer and a **streak**
  of consecutive days.
- **Reviews:** the most common 1–3 star complaint across couples apps is that everything
  worth using is behind the paywall, and Paired is the main target. Reviewers report a free
  tier with one teaser question a day and trials that converted to annual charges during
  onboarding [S16]. One reviewer wanted to skip sexual questions **without breaking the
  streak**: the streak was holding the couple hostage to content that didn't fit them
  [S17]. People like the deep conversations [S17].

### Locket and Between (ambient presence, archives) [S19][S20][S21]

- **Locket:** photos land directly on the partner's home-screen widget. A streak score
  (consecutive days of exchange) shows on the widget, and users **can turn it off** [S19].
  Gold adds features like more friends and camera-roll uploads [S19].
- **Between:** a private two-person messenger with a memory box, anniversary calendar,
  "D-day" counter and timeline. It has historically been freemium with paid cosmetics and
  backup [S20][S21].
- **Lesson:** presence on the home screen is what people love about both. An opt-out for
  streaks is the minimum courtesy.

### Background: why streaks between people are touchy [S22][S23]

Snapchat streaks get criticised as a dark pattern. Users send blank photos just to keep
the count alive, and press and academic work tie streaks to anxiety and fear of missing out
[S22][S23]. A couples app that makes a lapse look like *the partner* failed doubles that
pressure.

---

## 3. Synthesis

| Pattern | Seen in | Reviewer reaction | Use in Beyond? |
|---|---|---|---|
| Something visibly accumulates from small shared gestures | Forest, Finch, FurTwo | Strongly positive, "satisfying" | **Yes.** This is the core idea. |
| Lives on the home screen / widget | Locket, Widgetable, Couple Pulse | Positive, the most loved surface | Yes, later (widget) |
| Both partners contribute and it's shown as one thing | FurTwo, Couple Pulse reveal | Positive | Yes, without forced role splits |
| Needs stats / hunger / hygiene | FurTwo, Widgetable | Cute at first, then turns into chores | **No** |
| Death, running away, withering on neglect | Widgetable, Forest | Guilt, tears, "should be optional" | **No** |
| Streak counters | Paired, Locket, Snapchat | Pressure, held hostage by content | **No** (at most a quiet, opt-in tally with no penalty) |
| Paywalls on the core loop, ads to feed | Paired, Widgetable, FurTwo | Top complaint category | **No** (Beyond is open source and free) |
| Weekly subscriptions, $200 lifetime anchors | Couple Pulse, FurTwo | Distrust | **No** |
| Cosmetic, expressive rewards | Finch, Forest species | Positive | Yes, as free expression driven by the touches themselves |
| Real calendar seasons / life stages | Finch, FurTwo stages | Positive | Yes, tied to time and encounters, not effort |

**What to build on:** Bond Touch already has the right raw material. A touch is an
expressive, colourful gesture made of real finger motion, not a button press for points.
That lets growth *show what was said* instead of keeping score. None of the apps above
derives the shape of what grows from the gesture itself. That is the opening for Beyond.

---

## Sources

- [S1] Couple Pulse App Store listing (description, IAP list, version notes): https://apps.apple.com/us/app/id6757607240 · metadata via https://itunes.apple.com/lookup?id=6757607240&country=us
- [S2] Other same-name apps, for disambiguation: https://apps.apple.com/app/id6755443316 · https://apps.apple.com/dm/app/couples-questions-pulse/id1505114767 · https://www.trendingtopics.eu/pulse-vienna-startup-couples-health-data/
- [S3] Couple Pulse developer site: https://www.couplespaceinc.com/couplepulse
- [S4] Couple Pulse customer reviews (US/CA RSS): https://itunes.apple.com/us/rss/customerreviews/id=6757607240/sortby=mostrecent/json
- [S5] FurTwo App Store listing: https://apps.apple.com/us/app/furtwo-couples-virtual-pet/id6759111831
- [S6] FurTwo reviews: https://itunes.apple.com/us/rss/customerreviews/id=6759111831/sortby=mostrecent/json
- [S7] Widgetable App Store listing: https://apps.apple.com/us/app/widgetable-besties-couples/id1641107226
- [S8] Widgetable review summaries: https://kimola.com/reports/widgetable-virtual-pet-care-lock-screen-140828 · https://adapty.io/paywall-library/widgetable-pet-widget-theme/
- [S9] Widgetable recent reviews (US RSS, Oct 2026): https://itunes.apple.com/us/rss/customerreviews/id=1641107226/sortby=mostrecent/json
- [S10] Finch App Store listing: https://apps.apple.com/us/app/id1528595748
- [S11] Finch reviews: https://makeheadway.com/blog/finch-app-review/ · https://habitbox.app/blog/finch-app-review
- [S12] Finch breakdown: https://www.autonomous.ai/en-GB/ourblog/finch-self-care-app-review-full-breakdown
- [S13] Forest (Wikipedia): https://en.wikipedia.org/wiki/Forest_(application)
- [S14] Forest review: https://thesweetsetup.com/apps-we-love-forest/
- [S15] Forest parents' guide / toolkit: https://www.commonsensemedia.org/app-reviews/forest-stay-focused-be-present · https://abdn.ac.uk/toolkit/productivity/forest
- [S16] Couples apps ranked by complaint category: https://unstar.app/blog/paired-lasting-love-nudge-evergreen-cupla-couples-apps-ranked-2026
- [S17] Paired Google Play review analysis: https://kimola.com/reports/unlock-insights-paired-app-customer-feedback-analysis-google-play-en-144872
- [S18] Paired paywall: https://adapty.io/paywall-library/paired-couples-relationship/ · listing https://apps.apple.com/us/app/paired-couples-relationship/id1469609343
- [S19] Locket parental guide (streak score, opt-out, Gold): https://www.vodafone.co.uk/newscentre/smart-living/digital-parenting/digital-parenting-pro/locket/
- [S20] Between App Store listing: https://apps.apple.com/us/app/between-couples-love-tracker/id458035189
- [S21] Between vs. Connected comparison: https://connectedcouples.app/compare/connected-vs-between
- [S22] Snapchat streaks as a dark pattern: https://www.spiegeloog.amsterdam/hooked-on-snapchat/ · https://blogs.ubc.ca/etec523/2024/06/02/snapchat-streaks/
- [S23] CBS News, "Hooked on phones": https://cbsnews.com/news/hooked-on-phones
