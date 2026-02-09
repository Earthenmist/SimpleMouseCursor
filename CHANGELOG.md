## :jigsaw: Addon Updates (2026-01-14)

**Simple Mouse Cursor** — v1.0.1  

**Changes:**  
• Removed hard API version blocks that disabled functionality on Midnight (12.0.0+).  
• Replaced version-based guards with capability-based checks for better future compatibility.  
• Updated documentation to reflect full Midnight Beta support.

**Fixes:**  
• Re-enabled Health, Power, and GCD tracking for the Midnight Beta client.  
• Fixed a crash caused by Blizzard’s new “secret value” protections when reading health and power values.  
• Updated health and power ring calculations to use safe percentage-based APIs where required.  
• Improved safeguards to prevent arithmetic on protected values in future client builds.  
• Ensured GCD tracking works correctly without relying on restricted cooldown time values.

**Known issues:**  
• None currently known.
