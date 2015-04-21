using System;
using System.Data;
using System.Data.SqlClient;
using System.Collections.Generic;
using System.Configuration;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.VisualBasic.FileIO;

namespace JobOverlapChecker
{
    class Program
    {
        static int Main(string[] args)
        {
            // Parse our args, return if an error is found.
            InputParameters Parameters;

            try
            {
                Parameters = new InputParameters(args);
                Parameters.Validate();
            }
            catch (Exception e)
            {
                Console.WriteLine(e.ToString());
                return 1;
            }

            // Start
            Console.WriteLine(string.Format("Starting Overlap Checker: {0}", DateTime.Now));

            // Get the SQL Job data
            Console.WriteLine("Getting Job Data");
            JobData SQLJobData = null;
            try
            {
                SQLJobData = new JobData(Parameters);
            }
            catch(Exception e)
            {
                Console.WriteLine(e.ToString());
                return 1;
            }

            // Loop through jobs and calculate delays
            Console.WriteLine(string.Format("Checking Overlaps for {0} jobs.", SQLJobData.GetJobList().Count));
            foreach (var j in SQLJobData.Jobs)
            {
                Console.WriteLine(string.Format("Getting Overlap Data for job: {0}", j.jobID));
                
                // Create a collection of execution times for all jobs other than the current job
                double[][] otherExecs = SQLJobData.GetOtherJobExecutions(j.jobID);

                // Calculate the required job delay to reduce overlaps and set delay
                // on the object.
                SQLJobData.CommitDelay(j.jobID,j.CalculateDelay(otherExecs));
            }

            // Write data to SQL server if --calculate_only has not bee passed
            if (!Parameters.calculateOnly)
            {
                try
                {
                    SQLJobData.CommitToSQL(Parameters.sqlInstance);
                }
                catch
                {
                    Console.ReadKey();
                    return 1;
                }

            }

            // Complete
            Console.WriteLine(string.Format("Overlap Check Complete: {0}", DateTime.Now));
            return 0;
        }
    }

    public class InputParameters
    {
        // Set some vars
        public readonly string dataSource = string.Empty;
        public readonly string sqlInstance = string.Empty;
        public readonly string dataFilePath = string.Empty;
        public readonly bool calculateOnly = false;
        private readonly string usage = "Command Line Arguments:\n-d/--datasource <CSV|SQL>: Specifies the source of the job data\n-f/--filepath <path to CSV file>\n-i/--instance <sql instance>: This is the SQL instance the data will be read from/written to\n[--calculate_only]: Display the results without writing them to a table.";

        public InputParameters(string[] args)
        {
            // Check to see if we have any args
            // If so, use them, if not, fall back to the app.config and the local instance
            if (args.Length != 0)
            {
                for (int i = 0; i < args.Length; i++)
                {
                    switch (args[i])
                    {
                        case "-d":
                        case "--datasource":
                            i++;
                            if (args[i] == "SQL" || args[i] == "CSV")
                            {
                                dataSource = args[i];
                            }
                            break;
                        case "-f":
                        case "--filepath":
                            i++;
                            dataFilePath = args[i];
                            break;
                        case "-i":
                        case "--instance":
                            i++;
                            sqlInstance = args[i];
                            break;
                        case "--calculate_only":
                            calculateOnly = true;
                            break;
                    }
                }

                // Check to see if an instance was passed as an argument, if not, get it from the app.config
                if (string.IsNullOrEmpty(sqlInstance))
                {
                    sqlInstance = ConfigurationManager.AppSettings["Instance"];
                }
            }
            else
            {
                Console.WriteLine("No arguments given, trying to use app.config settings.");
                if (!string.IsNullOrEmpty(ConfigurationManager.ConnectionStrings["SQLData"].ConnectionString))
                {
                    dataSource = "SQL";
                    sqlInstance = ConfigurationManager.AppSettings["Instance"];
                    string connectionString = ConfigurationManager.ConnectionStrings["SQLData"].ConnectionString.Replace("Data Source=localhost", "Data Source=" + sqlInstance);
                }
                else if (!string.IsNullOrEmpty(ConfigurationManager.AppSettings["CSVData"]))
                {
                    dataSource = "CSV";
                    string CSVDataPath = ConfigurationManager.AppSettings["CSVData"];
                }
                else
                {
                    throw new System.Exception(string.Format("No suitable data sources found in the app.config, and no parameters sepcified.\n\n{0}",usage));
                }
            }
        }

        public string Validate()
        {
            var result = string.Empty;

            // Make sure our arguments validate.
            // Check to see if the dataSource was set
            if (string.IsNullOrEmpty(dataSource)){
                result = "A data source of either 'CSV' or 'SQL' is required.";
                result = string.Format("Error: {0}\n\n{1}",result,usage);
                throw new System.Exception(result);
            }

            // If CSV, make sure it is a valid file
            if (dataSource == "CSV" && (string.IsNullOrEmpty(dataFilePath) || !File.Exists(dataFilePath)))
            {
                result = "Data source of CSV specified, but no path was given, or the path is invalid.";
                result = string.Format("Error: {0}\n\n{1}",result,usage);
                throw new System.Exception(result);
            }

            // Check the instance to make sure we can connect, but only if we are committed data to SQL, or reading the job data from SQL
            if (!calculateOnly || dataSource == "SQL")
            {
                if (!string.IsNullOrEmpty(ConfigurationManager.ConnectionStrings["SQLData"].ConnectionString))
                {
                    string connectionString = ConfigurationManager.ConnectionStrings["SQLData"].ConnectionString.Replace("Data Source=localhost", "Data Source=" + sqlInstance);
                    SqlConnection conn = new SqlConnection(connectionString);
                    try
                    {
                        // Try to connect
                        conn.Open();
                    }
                    catch (Exception e)
                    {
                        result = string.Format("Invalid connection string: {0}\n Or server is not reachable.\nReported Error: {1}", connectionString, e.ToString());
                        result = string.Format("Error: {0}\n\n{1}",result,usage);
                        throw new System.Exception(result);
                    }

                    // Close the connection
                    conn.Close();
                }
                else
                {
                    result = "Connection string missing from app.config.";
                    result = string.Format("Error: {0}\n\n{1}",result,usage);
                    throw new System.Exception(result);
                }
            }   
            return result;
        }
    }

    public class JobData
    {
        // members
        public readonly List<Job> Jobs;

        // constructor(s)
        public JobData( InputParameters Parameters )
        {
            Jobs = new List<Job>();

            // Build the destination datatable
            var myJobData = new DataTable();
            myJobData.Columns.Add(new DataColumn("job_id", typeof(System.String)));
            myJobData.Columns.Add(new DataColumn("job_name", typeof(System.String)));
            myJobData.Columns.Add(new DataColumn("interval_sec", typeof(System.Int32)));
            myJobData.Columns.Add(new DataColumn("avg_dur", typeof(System.Int32)));
            myJobData.Columns.Add(new DataColumn("run_datetime", typeof(System.DateTime)));
            myJobData.Columns.Add(new DataColumn("end_datetime", typeof(System.DateTime)));


            // If source is  CSV, parse the CSV. Otherwise, connect to SQL.
            if ( Parameters.dataSource == "CSV" )
            {
                //Write to console
                Console.WriteLine(string.Format("Reading job data from file: {0}",Parameters.dataFilePath));

                // Parse data into a data table
                var myReader = new CSVReader();
                myJobData = myReader.GetDataTable(Parameters.dataFilePath);
            }
            else if (Parameters.dataSource == "SQL")
            {
                // Write to console
                Console.WriteLine(string.Format("Attempting to retrieve job data from a SQL server: {0}",Parameters.sqlInstance));

                // Connect to SQL
                var connectionString = ConfigurationManager.ConnectionStrings["SQLData"].ConnectionString.Replace("Data Source=localhost", "Data Source=" + Parameters.sqlInstance);
                var conn = new SqlConnection(connectionString);
                try
                {
                    // Try to connect
                    conn.Open();

                    // Retrieve Job Data
                    var jobDataCommand = new SqlCommand("GetJobData", conn);
                    jobDataCommand.CommandType = CommandType.StoredProcedure;
                    var dataReader = jobDataCommand.ExecuteReader();
                    myJobData.Load(dataReader);
                }
                catch (Exception e)
                {
                    // Throw any errors we get
                    throw new Exception(string.Format("Error: Invalid connection string: {0}\n Or server is not reachable.\nReported Error: {1}", connectionString, e.ToString()));
                }
            }

            // Read DataTable into a collection of Job objects
            // Get unique job_ids
            var dView = new DataView(myJobData);
            var jobList = dView.ToTable(true,new string[] {"job_id","job_name","interval_sec","avg_dur"});

            // Loop through unique jobs, create a job object, and add it to the collection
            foreach( DataRow jr in jobList.Rows )
            {
                // Get the job execution interval
                var i = jr.Field<Int32>("interval_sec");
                // Get the job_id
                var j = jr.Field<string>("job_id");                                
                // Get the average duration
                var a = jr.Field<Int32>("avg_dur");
                //Get the job name
                var jn = jr.Field<string>("job_name");

                // List to store the execution times
                var eList = new List<double[]>();

                foreach (DataRow r in myJobData.Rows)
                {
                    if (r.Field<string>("job_id") == j)
                    {
                        // Convert our current datetime to seconds since epoch
                        double run_datetime;
                        double end_datetime;

                        run_datetime = r.Field<DateTime>("run_datetime").Subtract(new DateTime(1970, 1, 1, 0, 0, 0, 0)).TotalSeconds;
                        end_datetime = r.Field<DateTime>("end_datetime").Subtract(new DateTime(1970, 1, 1, 0, 0, 0, 0)).TotalSeconds;
                        
                        eList.Add(new double[] { run_datetime, end_datetime });
                    }
                }

                // Instantiate a new Job object for the current job
                var currentJob = new Job(j, jn, i, a, eList);

                // Add our current job object to the collection
                Jobs.Add(currentJob);
            }
        }

        // methods
        // returns a unique list of jobs
        public List<string> GetJobList()
        {
            return (from j in Jobs select j.jobID).Distinct().ToList();
        }

        // Returns a list of double for every other job execution
        public double[][] GetOtherJobExecutions(string jid)
        {
            // Set an int to store our current position in the final array
            var arrayCurrentPosition = 0;

            // Stores the final length of the array
            var arrayLength = 0;
            
            // For each job (where the job_id is not the same as the current job) 
            // Count the number of executions and sum those to determine the final
            // array length.
            Jobs.Where(x => x.jobID != jid).ToList().ForEach(n => arrayLength += n.jobExecutions.Count);

            // Create a new double array using the length calculated above
            var oje = new double[arrayLength][];

            // For each job (where the job_id is not the same as the current job)
            // Get the list of executions and put them in the array
            foreach (var j in Jobs.Where(x => x.jobID != jid).ToList())
            {
                 for ( var i = 0; i < j.jobExecutions.Count; i++)   //double[] je in j.jobExecutions)
                 {                           
                     // Make sure to add the current delay when getting job execution times
                     oje[arrayCurrentPosition] = new double[] { j.jobExecutions[i][0] + j.delaySec, j.jobExecutions[i][1] + j.delaySec };
                     arrayCurrentPosition++;
                 }
            }

            return oje.OrderBy(x => x[0]).ToArray();
        }

        // Commits the delay to a given job
        public void CommitDelay(string jid, int d)
        {
            // Set the delay for the job
            for(int i = 0; i < Jobs.Count; i++)
            {
                if (Jobs[i].jobID == jid)
                {
                    Jobs[i].delaySec = d;
                }
            }
        }

        // Writes the calculated delays to SQL
        public void CommitToSQL(string instance)
        {
            var targetTable = ConfigurationManager.AppSettings["TargetTable"];

            // Create a data table to store our data
            var delayResults = new DataTable();
            delayResults.Columns.Add("job_name");
            delayResults.Columns.Add("delay_sec");

            // Populate the data table
            foreach (var j in Jobs)
            {
                var newRow = delayResults.NewRow();
                newRow["job_name"] = j.jobName;
                newRow["delay_sec"] = j.delaySec;

                delayResults.Rows.Add(newRow);
            }

            // Truncate the target table, then push the datatable to SQL
            // If this fails, job delays are dumped to the console
            try
            {
                var connectionString = ConfigurationManager.ConnectionStrings["SQLData"].ConnectionString.Replace("Data Source=localhost", "Data Source=" + instance);
                var conn = new SqlConnection(connectionString);
                conn.Open();

                // Truncate the target table
                var truncateCmd = new SqlCommand(string.Format("TRUNCATE TABLE {0};",targetTable),conn);
                truncateCmd.ExecuteNonQuery();

                // Insert to our target table
                var bulkCopy = new SqlBulkCopy(conn, SqlBulkCopyOptions.TableLock | SqlBulkCopyOptions.FireTriggers | SqlBulkCopyOptions.UseInternalTransaction, null);
                bulkCopy.DestinationTableName = targetTable;
                bulkCopy.WriteToServer(delayResults);
            }
            catch (Exception ex)
            {
                Console.WriteLine(string.Format("Error inserting delay data: {0}",ex.ToString()));
                Console.WriteLine("Dumping Delay Data:");
                for (var i = 0; i < delayResults.Rows.Count; i++)
                {
                    Console.WriteLine(string.Format("{0}: {1}",delayResults.Rows[i].Field<string>("job_name").ToString(),delayResults.Rows[i].Field<string>("delay_sec").ToString()));
                }

                throw new Exception();
            }
        }
    }

    public class Job
    {
        // member(s)
        public readonly string jobID;
        public readonly string jobName;
        private readonly int interval;
        private readonly int averageDuration;
        public int delaySec;
        public readonly List<double[]> jobExecutions;

        // constructor(s)
        public Job ( string j, string jn, Int32 i, Int32 a, List<double[]> e ){
            jobID = j;
            jobName = jn;
            interval = i;
            averageDuration = a;
            jobExecutions = e;
        }

        // method(s)

        // This does all the heavy-lifting, it loops though the executions for the current job
        // and compares it to every other execution.
        public Int32 CalculateDelay( double[][] j )
        {
            // Create a spinner to show progress
            var spin = new ConsoleSpiner();

            // Keep track of overlap count and delay count
            var overlapCount = 1;
            var lastOverlapCount = -1;
            var currentDelay = 0;
            var loopCount = 0;

            // Limit the number of runs for our overlap checking loop
            var loopLimit = (interval / 2) - averageDuration;

            while (loopCount < loopLimit && overlapCount > 0)
            {
                // Reset our overlap count to 0
                overlapCount = 0;

                // For each job execution , get a count of overlapping jobs
                Parallel.For(
                    0,
                    jobExecutions.Count,
                    () => 0,
                    (je, loop, subtotal) =>
                    {
                        var run_datetime = jobExecutions[je][0] + loopCount;
                        var end_datetime = jobExecutions[je][1] + loopCount;

                        for (var i = 0; i < j.Length; i++)
                        {
                            if (j[i][0] <= end_datetime && j[i][1] >= run_datetime)
                            {
                                subtotal++;
                            }
                        }

                        return subtotal;
                    },
                    (x) =>
                    {
                        Interlocked.Add(ref overlapCount, x);
                    }
                );
                
                // Show some progress
                //spin.Turn();

                // This just catches it the first time this runs
                if (lastOverlapCount == -1)
                {
                    Console.WriteLine(string.Format("Initial Overlaps: {0}",overlapCount));
                    lastOverlapCount = overlapCount;
                    currentDelay = 1;
                }

                // Only set the delay if we made an improvment
                if (overlapCount < lastOverlapCount)
                {
                    currentDelay = loopCount;
                    lastOverlapCount = overlapCount;
                }

                // Increment our loop counter by 2 - speeds things up with
                // little downside
                loopCount += 2;
            }
            Console.WriteLine(string.Format("Delay: {0}\nFinal Overlaps: {1}\n", currentDelay, lastOverlapCount));

            return currentDelay;
        }
    }

    public class ConsoleSpiner
    {
        int counter;
        public ConsoleSpiner()
        {
            counter = 0;
        }
        public void Turn()
        {
            counter++;
            switch (counter % 4)
            {
                case 0: Console.Write("|"); break;
                case 1: Console.Write("/"); break;
                case 2: Console.Write("-"); break;
                case 3: Console.Write("\\"); break;
            }
            Console.SetCursorPosition(Console.CursorLeft - 1, Console.CursorTop);
        }
    }

    public class CSVReader
    {
        // Simple CSV reader class

        public System.Data.DataTable GetDataTable(string strFileName)
        {
            DataTable csvData = new DataTable();
            try
            {
                using (TextFieldParser csvReader = new TextFieldParser(strFileName))
                {
                    csvReader.SetDelimiters(new string[] { "," });
                    csvReader.HasFieldsEnclosedInQuotes = true;
                    //read column names
                    string[] colFields = csvReader.ReadFields();
                    foreach (string column in colFields)
                    {
                        DataColumn datecolumn = new DataColumn(column);
                        datecolumn.AllowDBNull = true;
                        csvData.Columns.Add(datecolumn);
                    }
                    while (!csvReader.EndOfData)
                    {
                        string[] fieldData = csvReader.ReadFields();
                        //Making empty value as null
                        for (int i = 0; i < fieldData.Length; i++)
                        {
                            if (fieldData[i] == "")
                            {
                                fieldData[i] = null;
                            }
                        }
                        csvData.Rows.Add(fieldData);
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(ex.Data);
            }
            return csvData;
        }
    }
}