# Architecture Overview

This document outlines the high-level architecture of Neura Companion.

## Modules

1. **Authentication & Profiles**  
   - Firebase Auth  
   - Profile management, secure storage  

2. **Security & Compliance**  
   - Local Authentication (biometrics)  
   - Data encryption, GDPR/CCPA flow  

3. **Ritual & Usage Analytics**  
   - Hive local storage  
   - CSV & PDF export  
   - Charts with FL_Chart and filters  

4. **Social & Community**  
   - Firestore backend  
   - Feed, Comments, Challenges, Leaderboard  

5. **Dream & Sleep Features**  
   - Audio recording, Transcription  
   - AI-driven dream interpretation  
   - Calendar & visualizer UI  

6. **Voice & Journaling**  
   - Speech-to-text journaling  
   - Emotion analysis  
   - AI-driven prompts & reflections  

7. **Offline Mode & Sync**  
   - Connectivity detection  
   - Two-way sync & conflict resolution  

8. **AI Companion & Mascot**  
   - Avatar selection & animations  
   - Dual-AI chat interface  

9. **Monetization & Billing**  
   - In-app purchases & Stripe integration  

10. **CI/CD & Deployment**  
    - GitHub Actions  
    - Firebase Hosting & desktop installer scripts
