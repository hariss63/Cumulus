global class BGE_HandsOnGridController {


    public static String jsonString {get; set;}
    public static String jsonUpdatedString {get; set;}
    public static String jsonColumnsString {get; set;}

    private static Id batchId;
    private static Id templateId;

    private static List<DataImport__c> data;
    private static List<BGE_DynamicalColumnWrapper> columns;
    private static Map<String, Schema.SObjectField> fieldsMap = Schema.SObjectType.DataImport__c.fields.getMap();

    public List<DataImport__c> errorRecords {get;set;}
    public List<DataImport__c> successRecords {get;set;}

    public Boolean validated {get; set;}

    private static Batch_Template_Field__c[] templateFields;


    public BGE_HandsOnGridController() {

        // Initialize variables.
        errorRecords = new List<DataImport__c>();
        successRecords = new List<DataImport__c>();

        // Get the BatchId from the URL.
        findBatchId();
        findTemplateId();

        // Get all Template fields and load columns.
        loadDynamicColumns();

        // Convert loaded Template Fields objects into a JSON String to display dynamic columns.
        jsonColumnsString = JSON.serialize(columns);

        // Get all the Data Import sObjects from the Batch.
        loadData(batchId);

        // Convert loaded Data Import objects into a JSON String.
        // Variable json String will be used to load the data into the grid.
        jsonString = JSON.serialize(data);
    }

    private static void findBatchId() {

        batchId = ApexPages.currentPage().getParameters().get('batchid');
    }

    private static void findTemplateId() {

        DataImportBatch__c[] batches = new DataImportBatch__c[]{};

        batches = [SELECT Id,
                        Batch_Template__c
                    FROM DataImportBatch__c
                    WHERE Id =: batchId
                    LIMIT 1];

        if (!batches.isEmpty()) {
            templateId = batches[0].Batch_Template__c;
        }
    }

    private static void loadDynamicColumns() {

    //    Batch_Template_Field__c[] templateFields = new Batch_Template_Field__c[]{};
        templateFields = new Batch_Template_Field__c[]{};

        BGE_DynamicalColumnWrapper column;
        columns = new BGE_DynamicalColumnWrapper[]{};

        templateFields = [SELECT Id,
                                Name,
                                Order__c,
                                Read_Only__c,
                                Required__c,
                                Sticky_Field__c,
                                Sticky_Field_Value__c,
                                Sticky_Field_Visibility__c
                            FROM Batch_Template_Field__c
                            WHERE Batch_Template__c =: templateId
                            ORDER BY Order__c ASC
                            LIMIT 10000];

        for (Batch_Template_Field__c field : templateFields) {

            column = new BGE_DynamicalColumnWrapper(field);
            columns.add(column);
        }
    }

    /*
     * Load data for the grid based on Batch Id
     * @Param batchId - Id reference to the current Batch used in the grid
     */
    private static void loadData(Id pBatchId) {


        String query = 'SELECT ';

        for (Batch_Template_Field__c field : templateFields) {

            // This is the first record avoid adding the ',' character
            if (field.Id == templateFields[0].Id) {

                query = query + field.Name;
            }
            else {

                query = query + ', ' + field.Name;
            }

        }

        query = query + ' FROM DataImport__c WHERE NPSP_Data_Import_Batch__c = \'' +  pBatchId +'\'' + ' ORDER BY createdDate ASC LIMIT 5000';

        system.debug('QUERY    ' + query);

        data = Database.query(query);
    }

    /*
     * Adds a new Data Import from the json data
     * @Param jsonData - data to create the Data Import
     * @Returns ResponseWrapper
     */
    @RemoteAction
    global static ResponseWrapper save(Id rowId, String pBatchId, String jsonData) {

        ResponseWrapper response = new ResponseWrapper();

        JSONParser parser = JSON.createParser(jsonData);

        try {

            DataImport__c newDataImport = (DataImport__c) parser.readValueAs(Type.forName('DataImport__c'));

            newDataImport.NPSP_Data_Import_Batch__c = pBatchId;

            if (rowId != null && !String.isEmpty(rowId)) {

                newDataImport.Id = rowId;
            }

            upsert newDataImport;

            response.addDataImportId(newDataImport.Id);

            response.addMessage('Data Import successfully created or updated');
        }
        catch (Exception e) {

            String error = e.getStackTraceString();

            response.addError(error);
        }

        return response;
    }

    /*
     * Adds many new Data Import records from the json data
     * @Param jsonData - data to create the Data Import
     * @Returns ResponseWrapper
     */
    @RemoteAction
    global static ResponseWrapper saveAll(String pBatchId,String jsonData) {

        ResponseWrapper response = new ResponseWrapper();

        // Parse entire JSON response.
        JSONParser parser = JSON.createParser(jsonData.replace('""', 'null'));

        List<DataImport__c> sObjectsToInsert = new List<DataImport__c>();
        List<DataImport__c> sObjectsToUpdate = new List<DataImport__c>();

        // To avoid having duplicates at the list.
        Set<Id> existingIds = new Set<Id>();

        try {

            while (parser.nextToken() != null) {

                // Start at the array of data imports.
                if (parser.getCurrentToken() == JSONToken.START_ARRAY) {

                    while (parser.nextToken() != null) {

                        // Advance to the start object marker to
                        //  find next Data Import object.
                        if (parser.getCurrentToken() == JSONToken.START_OBJECT) {

                            // Read entire Data Import object.
                            Map<String, String> wrap = (Map<String, String>)parser.readValueAs(Map<String, String>.class);

                            Set<String> keySet = wrap.keySet();

                            DataImport__c newDataImport = new DataImport__c();

                            checkType(wrap, newDataImport, keySet);

                            // Insert and upsert are done separately so we can include the ids of the new rows and avoid bugs.
                            if (newDataImport.id == null) {

                                newDataImport.NPSP_Data_Import_Batch__c = pBatchId;

                                sObjectsToInsert.add(newDataImport);

                                response.addMessage('Data Import successfully created or updated');
                            }
                            else {

                                sObjectsToUpdate.add(newDataImport);
                            }

                            // Skip the child start array and start object markers.
                            parser.skipChildren();
                        }
                    }
                }
            }

            // If there are new rows.
            if (!sObjectsToInsert.isEmpty()) {

                // The last row is always blank, remove it.
                sObjectsToInsert.remove(sObjectsToInsert.size()-1);

                try{

                    // Insert them
                    insert sObjectsToInsert;

                    // Add the Ids of the newly created objects to the table.
                /*    for (DataImport__c currentNewDataImport : sObjectsToInsert) {

                        if (currentNewDataImport != null) {

                            response.addDataImportId(currentNewDataImport.Id);
                        }
                    }*/

                    // Send a message to the user.
                    response.addMessage('rows inserted correctly');
                }
                catch(DmlException dmlE){

                    String error = dmlE.getStackTraceString();

                    // Send a message to the user.
                    response.addError(error);
                }

            }
            // For updated rows
            if (!sObjectsToUpdate.isEmpty()) {

                try{

                    // Do the update.
                    update sObjectsToUpdate;

                    // Send a message to the user.
                    response.addMessage('rows updated correctly');
                }
                catch(DmlException dmlE){

                    String error = dmlE.getStackTraceString();

                    // Send a message to the user.
                    response.addError(error);
                }
            }
        }
        catch (Exception e) {

            String error = e.getStackTraceString();

            response.addError(error);
        }

        return response;
    }

    private static void checkType(Map<String, String> wrap, DataImport__c newDataImport, set<String> keySet) {

        if (!keySet.isEmpty()) {

            // as we are sending changes on the JSON, the fields we are using may vary
            // therefore loop over the values sent on the JSON.
            for (String key : keySet) {

                if (wrap.containsKey(key)) {

                    if (wrap.get(key) != null){

                        Schema.SObjectField field = fieldsMap.get(key);

                        Schema.DisplayType fldType = field.getDescribe().getType();

                        // Assign value from the JSON to the corresponding field in the data import.
                        if (fldType != Schema.DisplayType.String) {

                            if (fldType == Schema.DisplayType.Id){

                                Id idField = wrap.get(key);
                                newDataImport.put(key,idField);
                            }
                            else if (fldType == Schema.DisplayType.Date) {

                                Date dateField = system.today();

                                try{

                                    dateField = Date.valueOf(wrap.get(key));
                                }
                                catch(TypeException e){

                                    // If date format was incorrect.
                                    dateField = Date.parse(wrap.get(key));
                                }

                                newDataImport.put(key,dateField);
                            }
                            else if (fldType == Schema.DisplayType.DateTime) {

                                DateTime dateTimeFIeld = system.now();

                                try{

                                    dateTimeFIeld = DateTime.parse(wrap.get(key));
                                }
                                catch(TypeException e){

                                    dateTimeFIeld = DateTime.valueOf(wrap.get(key));
                                }

                                newDataImport.put(key,dateTimeFIeld);
                            }
                            else if (fldType == Schema.DisplayType.Double){

                                Double doubleField = Double.valueOf(wrap.get(key));
                                newDataImport.put(key,doubleField);
                            }
                            else if (fldType == Schema.DisplayType.Boolean){

                                Boolean booleanField = Boolean.valueOf(wrap.get(key));
                                newDataImport.put(key,booleanField);
                            }
                            else if (fldType == Schema.DisplayType.Currency) {

                                Decimal currencyField = Decimal.valueOf(wrap.get(key));
                                newDataImport.put(key,currencyField);
                            }
                            else if(fldType == Schema.DisplayType.Integer){

                                Integer integerField = Integer.valueOf(wrap.get(key));
                                newDataImport.put(key,integerField);
                            }
                        }
                        else {

                            newDataImport.put(key,wrap.get(key));
                        }
                    }
                }
            }
        }
    }


    /*
     * Deletes many Data Import objects from the json data
     * @Param batchIds - Ids of the Data Imports to delete.
     * @Returns ResponseWrapper
     */
    @RemoteAction
    global static ResponseWrapper deleteAll(List<String> batchIds) {

        ResponseWrapper response = new ResponseWrapper();

        try {

            // Check that we have received the Ids from the Javascript controller.
            if (batchIds != null && !batchIds.isEmpty()) {

                // Assign the objects to a list to ease debugging and defensive programming.
                List<DataImport__c> dataImportsToDelete = [SELECT Id, Donation_Name__c from DataImport__c WHERE Id IN: batchIds];

                // Check that we have received the objects from the Salesforce database.
                if (dataImportsToDelete != null && !dataImportsToDelete.isEmpty()) {

                    delete dataImportsToDelete;

                    response.addMessage('Data Import records successfully deleted');
                }
                else{

                    response.addMessage('No record was found on the database.');
                }
            }
            else {

                response.addMessage('No record was sent for deletion');
            }
        }
        catch (Exception e) {

            String error = e.getStackTraceString();

            response.addError(error);
        }

        return response;
    }


    // Save all rows to the database.
    public void continueToValidation(){

        if (data != null && !data.isEmpty()) {

            Database.UpsertResult[] lsr = Database.upsert(data, false);
            Integer index = 0;

            if (!lsr.isEmpty()) {

                for (Database.UpsertResult sr : lsr) {

                    try {

                        if (sr.isSuccess()) {

                            successRecords.add(data[index]);
                        }
                        else if (!sr.isSuccess()) {

                            errorRecords.add(data[index]);
                        }
                    }
                    catch(Exception ex) {

                        system.debug('EXCEPTION MESSAGE:    ' + ex.getMessage());
                    }

                    index++;
                }
            }
        }

        data = errorRecords;

        jsonString = JSON.serialize(data);

        validated = true;
    }

    /*
    * Run Dry Run process - and display errors is something goes wrong.
    * For now we wanna simulate the integration of process and display a test array of errors
    * @Returns ResponseWrapper
    */
    @RemoteAction
    global static ResponseWrapper dryRunProcess() {

        ResponseWrapper response = new ResponseWrapper();
        String[] simulateArrayErrors = new String[]{};

        simulateArrayErrors.add('Exists an inactive campaign, please validate');

        for (String error : simulateArrayErrors) {

            response.addMessage(error);
        }

        return response;
    }

    private static String reloadData(String pBatchId) {

        String jsonUpdatedString = '';

        // Get all the Data Import sObjects from the Batch.
        loadData(pBatchId);

        for (DataImport__c obj : data) {

            if (!String.isEmpty(jsonUpdatedString)) {

                jsonUpdatedString = jsonUpdatedString  + ',' + JSON.Serialize(obj);
            }
            else {

                jsonUpdatedString = jsonUpdatedString  + JSON.Serialize(obj);
            }
        }

        return jsonUpdatedString;
    }


    global class ResponseWrapper {

        public Boolean success { get; set; }
        public String[] messages { get; set; }
        public String[] dataImportIds { get; set; }



        //Constructor
        public ResponseWrapper() {

            success = true;
            messages = new String[]{};
            dataImportIds = new String[]{};
        }


        /*
         * add a message with the Id to the list.
         * @Param message - message to add
         */
        public void addMessage(String message) {

            messages.add(message);
        }


        /*
         * add am error message to the list.
         * @Param message - message to add
         */
        public void addError(String errorMessage) {

            success = false;
            addMessage(errorMessage);
        }

        public void addDataImportId(String dataImportId) {

            dataImportIds.add(dataImportId);
        }
    }
}