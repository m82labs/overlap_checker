#Overlap Checker
Application to reduce SQL Agent Job overlaps by introducing calculated job delays.

##Overview##
For a quick overview, please read my blog post on this project: 

##Installation##
Installation is fairly straight forward:
  1. Clone this repo.
  2. Open the solution and build it.
  3. Run `SQL Scripts\deploy.sql` on any instance you want to run the Overlap Checker on.

***WARNING: Read through the deploy.sql script, it will create various database objects and add a new 'Deploy' step to ALL jobs on the instance.***
 
##Troubleshooting##
Coming Soon

##Disclaimer##
This is my first time posting C# code to Git, and my second time ( maybe third) ever writing C#. Feedback is **VERY** welcome.
