-- To make this script accessible via the Service tab from any application (or a specific one, like Finder)
-- 1. open Automator & create a Quick Action
-- 2. workflow options should be: receives "no input" in "any application" (or whichever you prefer)
-- 3. paste the below into a "Run AppleScript" action and save it

do shell script "killall NotificationCenter"