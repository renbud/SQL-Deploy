# SQL-Deploy
Deploy SQL-Server scripts to multiple environments.

This is a command line utility that deploys the SQL files in a nominates folder to a nominated SQL-Server.
This utility was developed to allow command line deployments with logging and auditing of the deployment at a folder level, rather than an individual script level. Deployments are tracked in the target database in a deploy.Feature table.

Dependencies:
  1. Powershell 3.0
  2. SQLCMD.exe (Comes with SQL Server client tools)
  3. Tested with SQL Server 2012, 2016, 2017, but should work with any version of SQL server that supports SQLCMD.

## Behaviour
### Summary
A typical command is:
> SQL-Deploy.ps1 -EnvName *dev* -DeploymentRoot *I:\SQLDeployments* -DeploymentFolder *2018\TestDeploy*

This
a. Deploys the SQL scripts in I:\SQLDeployments\2018\TestDeploy to the server configured in the environment called "*dev*".
b. Logs the he process in a table called *deploy.Feature* in the database

### Detail
#### Executing
* SQL scripts are run in alphabetic order. When creating scripts name them according to the order you want them to execute.
* SQL-Deploy generates a file called _master.osql. This file uses the :r command to execute each sql script in turn. A new line and batch terminator (GO) is added between scripts.
* SQL-Deploy does not add any transactions to the scripts, so you are free to use transactions (or not) in your SQL code.
#### Error Handling
* SQL Deploy uses the :on error exit (-b) option of SQLCMD.exe.
* If an error occurs in one of your SQL scripts, execution is stopped and subsequent scripts are not executed.
* The error is detected by powershell which records the status of the feature as *Error*.
* Error messages are recorded in a log file (called *<env>_master.log*).
* The entire log, including the error message is also sent to standard output.
#### Hashing
* SQL-Deploy uses a hashing mechanism to track changes and avoid running the same deployment twice
* A cryptographic hash is calculated over the contents of the SQL files in the deployment folder.
* The hash is stored in the deploy.Feature table on the target database - keyed by the deployment folder name (a.k.a. *Feature*)
* If the hash of the deployment folder is the same as the hash stored in the database and the status of the deployment in the database is *Deployed*, then SQL-Deploy exits with a message saying the deployment is already done.
* If the contents of any SQL script in the folder is changed, the hash changes and SQL-Deploy will run all the scripts when it is executed.

#### Removal scripts
You may want to remove a feature from the target database. SQL-Deploy allows you to do this. It runs the scripts in the "Remove" subfolder under the Deployment Folder, and then updates the deploy.Feature table to mark the feature as *Removed*.
The following command removes the *2018\TestDeploy* feature:
> SQL-Deploy.ps1 -EnvName *dev* -DeploymentRoot *I:\SQLDeployments* -DeploymentFolder *2018\TestDeploy* **-Remove**
* SQL-Deploy requires the "Remove" subfolder to exist and contain  SQL scripts.
* SQL-Deploy does not currently require the feature to be deployed to allow its removal.
  

## Configuring an Environment
* It is not necessary to supply a server name, database name, user name and password to SQL-Deploy if the environment has already been configured.
* Environments are kept in in %APPDATA%\Sql-Deploy\config.json
* The environment can be created or edited by running Sql-Config.ps1.
> SQL-Config.ps1 -EnvName dev -S MyTargetDevServer -d MyTargetDevDatabase -U DeploymentUser -P MySillyPassword
* This script will prompt for values if they are not provided on the command line.
* The password is stored securely encrypted using the machine key and can only be accessed by the same user that stored it on the same machine that stored it.
* SQL-Deploy can be run without pre-configuring an environment by providing the same parameters directly. For example the following can be used withou configuring the *dev* environment. This could be used by a tool such as Octopus Deploy which has it's own concept of environments.
> SQL-Deploy.ps1 -EnvName *dev* -DeploymentRoot *I:\SQLDeployments* -DeploymentFolder *2018\TestDeploy*  -S MyTargetDevServer -d MyTargetDevDatabase -U DeploymentUser -P MySillyPassword
