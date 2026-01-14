📜 Changelog – Version 1.0.1  
  
📅 Release Date: 14-01-2026  
  
🆕 Midnight Beta Compatibility Update  
🛠️ Fixes & Improvements  
  
Re-enabled Health, Power, and GCD tracking for the Midnight Beta client.  
Fixed a crash caused by Blizzard’s new “secret value” protections when reading health and power values.  
Updated health and power ring calculations to use safe percentage-based APIs where required.  
Improved internal safeguards to prevent arithmetic on protected values in future client builds.  
Ensured GCD tracking functions correctly without relying on restricted cooldown time values.  
  
🔄 Changes  
  
Removed hard API version blocks that disabled functionality on Midnight (12.0.0+).  
Replaced version-based guards with capability-based checks for better future compatibility.  
  
📘 Documentation  
  
Removed outdated note stating that GCD, Health, and Power tracking were disabled in the Midnight Beta.  
Updated documentation to reflect full Midnight Beta support.  
  
✅ Compatibility  
  
World of Warcraft Retail, including Midnight on release  
