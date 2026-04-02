# Launch Strategy Research for FormationFlow

This document outlines research on launch strategies for a niche sports coaching app like FormationFlow.

## 1. Soft Launch vs. Hard Launch

The consensus is to use a phased approach: a soft launch to test and refine, followed by a hard launch to scale.

### Soft Launch

A soft launch is a limited release to a small, targeted audience to gather data, find bugs, and validate the product with minimal risk.

**Best Practices:**

*   **Targeted Market:** Launch in a smaller, representative market with lower user acquisition costs. For a US-targeted app, good options are **Canada, Australia, or Ireland**.
*   **Focus on Retention:** Key metrics are Day 1, Day 7, and Day 30 retention. A hard launch is not advisable if users are not returning.
*   **Technical Stability:** Monitor server load, API performance, and aim for a crash-free rate above 99%.
*   **Iterate Quickly:** Be prepared to release updates based on user feedback and analytics.

### Hard Launch

A hard launch is a full-scale release across all target markets with a coordinated marketing effort.

**Best Practices:**

*   **Coordinated Marketing:** A "burst" of PR, social media, influencer marketing, and paid ads to trigger app store algorithms.
*   **App Store Optimization (ASO):** Use learnings from the soft launch to optimize screenshots, videos, and keywords.
*   **Incentivize Early Adopters:** Offer launch-day rewards or discounts.
*   **Engage with Reviews:** Respond to all reviews in the first 48 hours to show the app is well-supported.

### Recommended Workflow

1.  **Alpha/Beta (Internal):** Test with a small group of users via TestFlight.
2.  **Soft Launch (Proxy Market):** Release in a market like Canada to optimize retention and fix bugs.
3.  **Optimization:** A/B test the app store listing and onboarding process.
4.  **Hard Launch (Global):** Once retention targets are met, execute the full marketing campaign.

## 2. Press and Review Sites

A mix of sports-specific media, app review sites, and general PR distribution is the best approach.

### Top-Tier Sports Tech News

*   **SportTechie:** Premier source for sports tech news.
*   **Sports Business Journal (SBJ) Tech:** Focuses on sports, business, and innovation.
*   **SportsPro Media (Tech Section):** Global sports business media with a focus on tech.
*   **GeekWire (Sports Tech):** Major tech news site with a dedicated sports tech vertical.

### Niche App Review & Submission Sites

*   **MobileAppDaily:** Large platform for app reviews and "Best of" lists.
*   **Product Hunt:** Essential for any new app launch; community-driven.
*   **Appedus:** Focuses on indie developers and offers free review submissions.
*   **BetaList:** For pre-launch apps to gather initial users.
*   **AppAdvice:** High-traffic site for iOS app news.

### Press Release Distribution

*   **Free/Low-Cost:** PRLog, PR.com, OnlinePRNews.
*   **Premium:** PR Newswire, eReleases.

**Pro-Tip:** When pitching sports tech sites, send a personalized pitch explaining how FormationFlow solves a specific problem for coaches, rather than a generic press release.

## 3. Ethical Tactics for Early Review Generation

Focus on community building and timing your requests.

### Pre-Launch

*   **Beta Testers:** Engage with beta testers on platforms like TestFlight. Use communities on Reddit (e.g., r/alphaandbetausers) to recruit. Ask for honest feedback, and happy testers are likely to leave reviews at launch.

### Post-Launch

*   **In-App Prompts:** Use Apple's native `SKStoreReviewController` to ask for reviews in-app.
    *   **Timing:** Trigger the prompt after a user has a "wow moment" (e.g., successfully creating a complex formation, saving a routine).
    *   **Frequency:** Do not interrupt the user's workflow and don't ask too often.
*   **Personal Outreach:** Ask your personal network for honest reviews. Reach out to micro-influencers in the cheerleading or dance space.
*   **Exceptional Support:** Provide a clear "Contact Us" or "Send Feedback" option. After you solve a user's problem, they are much more likely to leave a positive review if asked.
*   **Incentivize Feedback, Not Ratings:** It is against App Store rules to offer rewards for 5-star reviews.
    *   **Ethical Alternative:** Offer a small incentive (e.g., a free month of the pro tier) for completing a feedback survey. At the end of the survey, if the user is happy, you can ask them to share their thoughts on the App Store.

**What to Avoid:**

*   **Review Exchange Groups:** Do not use services that promise reviews in exchange for reviews. This can get your app banned.
