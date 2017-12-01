/*
    Copyright (c) 2017, Salesforce.org
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Salesforce.org nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.org
* @date 2017
* @group Rollups
* @group-content ../../ApexDocContent/Rollups2.htm
* @description Customizable Rollups service methods specific to Batch and Queueable rollup operations
*
*/
public class CRLP_RollupProcessor_SVC {

    public Enum ProcessingMode {
        NonLDV, LDV
    }

    /**
     * @description Processing Options to use for the startRollupsProcess
     */
    public class ProcessingOptions {
        public ProcessingMode mode = ProcessingMode.NonLDV;  // default to non-ldv mode
        public SObjectType parentObjType;
        public String parentKeyField;       // Needed
        public List<CRLP_Rollup> rollups;   // Stateful rollups collection for LDV Mode
    }

    /**
     * @description used to recieve and return the last Parent record id processed by startRollupsForLDV().
     * The value is saved as a stateful var in the calling batch process
     */
    private static Id lastParentIdProcessed;

    /** @description In LDV processing mode, the calling batch class needs to 'remember' the last parent Id processed
     * in the group to know where it left off in the next batch iteration
     * @return Id last processed
     */
    public static Id getLastProcesssedParentId() {
        return lastParentIdProcessed;
    }

    /**
     * @description The main work engine for roll-up activities. This method is called from both batch jobs
     * as well as from queuable jobs (via a trigger operation). Accepts a collection of summary OR detail records
     * and a ProcessingOptions object instance that defines the parameters to use for the rollup work.
     * @param summaryRecords Summary Records
     * @param detailRecords Deatil Records for the related Summary Records
     * @param options ProcessingOptions
     * @return List<SObject> Records that require updating.
     */
    public static List<SObject> startRollupProcess(List<SObject> summaryRecords, List<SObject> detailRecords, ProcessingOptions options) {

        // Convert the details list into a Map of details by ParentId
        Map<Id, List<SObject>> mapOfDetailsByParentId = new Map<Id, List<SObject>>();
        for (SObject dtl : detailRecords) {
            Id parentId = (Id) dtl.get(options.parentKeyField);
            if (!mapOfDetailsByParentId.containsKey(parentId)) {
                mapOfDetailsByParentId.put(parentId, new List<SObject>());
            }
            mapOfDetailsByParentId.get(parentId).add(dtl);
        }

        Type handlerClass = getHanderClassType(summaryRecords[0].getSobjectType());

        if (summaryRecords == null) {
            Set<Id> parentIds = mapOfDetailsByParentId.keySet();
            String soql = CRLP_Query_SEL.getResultsQuery(options.parentObjType) + ' WHERE Id IN :parentIds';
            summaryRecords = database.query(soql);
        }

        // Loop through each of the detail records and call the appropriate handler processing method
        Map<Id, SObject> recordsToUpdate = new Map<Id, SObject>();
        for (SObject parent : summaryRecords) {
            Id parentId = (Id) parent.get('Id');

            // Clear the list of stateful rollups anytime the parent Id changes
            if (options.mode == ProcessingMode.LDV && lastParentIdProcessed != parentId) {
                options.rollups.clear();
                lastParentIdProcessed = parentId;
            }

            List<SObject> detailsForParent = mapOfDetailsByParentId.get(parentId);
            SObject updatedRecord = completeRollupForParent(parent, detailsForParent, options);
            if (CRLP_Rollup_SVC.resultsNeedUpdate(parent, updatedRecord, options.rollups)) {
                recordsToUpdate.put(parentId, updatedRecord);
            }
        }

        // When running in LDV mode, the last ParentId process should NOT be updated yet (in the batch iteration).
        // This is necessary to handle the situation when a single Parent record may have thousands of detail records
        // passed through multiple batch iterations. The 'final' record will be handled by the finish() method of
        // the LDV Batch job.
        if (options.mode == ProcessingMode.LDV && lastParentIdProcessed != null) {
            recordsToUpdate.remove(lastParentIdProcessed);
        }

        return recordsToUpdate.values();
    }

    /**
     * @description Returns the Type of the appropriate CRLP_RollupXXXX_SVC class to use for handling the
     * rollups based on the SObjectType of the Summary object
     * @param objType Summary Object Type
     * @return ApexClassType
     */
    private static Type getHanderClassType(SObjectType objType) {
        Type handlerClass;
        if (objType == Account.SObjectType) {
            // Opportunity and Payment to Account
            handlerClass = CRLP_RollupAccount_SVC.class;

        } else if (objType == Contact.SObjectType) {
            // Opportunity and Payment  to Contact
            handlerClass = CRLP_RollupContact_SVC.class;

        } else if (objType == General_Accounting_Unit__c.SObjectType) {
            // Allocation to GeneralAccountingUnit
            handlerClass = CRLP_RollupGAU_SVC.class;

        } else if (objType == OpportunityContactRole.SObjectType) {
            // TODO OpportunityContactRole to Account & Contact
            // handlerClass = TBD;

        }
        return handlerClass;
    }

    /**
     * @description For given set of Summary records, returns a List of the related Detail records.
     * @param summaryRecords List<SObject>
     * @return List<SObject> detailRecords to roll up to the summary records
     */
    public static List<SObject> getDetailRecordsFromParentRecords(List<SObject> summaryRecords) {
        // Get the parent record Id's
        Set<Id> summaryRecordIds = new Set<Id>();
        for (SObject s : summaryRecords) {
            summaryRecordIds.add((Id)s.get('Id'));
        }

        String detailsQuery = CRLP_Query_SEL.getFullDetailsQueryForSummaryRecords(summaryRecordIds);
        return database.query(detailsQuery);
    }

    /**
     * @description For a given set of records, returns a Set<Id> of parent records using the passed field name as the parent
     * @param detailRecords List<SObject>
     * @param parentKeyField API Name of the parent field to use for the Id
     * @return Set<Id>
     */
    public static Set<Id> getParentIdsFromDetailRecords(List<SObject> detailRecords, String parentKeyField) {
        Set<Id> parentIds = new Set<Id>();
        for (SObject dtl : detailRecords) {
            if (dtl.get(parentKeyField) != null) {
                parentIds.add((Id)dtl.get(parentKeyField));
            }
        }
        return parentIds;
    }

    /**
     * @description For a given Parent (Summary) record, and set of detail records, complete the rollup of the
     * details to the parent. The List<CRLP_Rollup> collection in ProcessingOptions is used for the actual rollup
     * accumulations.
     * @param parent Summary SObject record
     * @param details list of Detail SObject records for a given parent Summary record
     * @param options ProcessingOptions. Contains List<CRLP_Rollup> rollup instances provided by the Batch class.
     * @return an updated Summary SObject (regardless of whether it actually requires updating or not)
     */
    public static SObject completeRollupForParent(SObject parent, List<SObject> detailRecords, ProcessingOptions options) {
        // The Parent record Id has changed, so initiate the rollup and determine if the Summary record
        // has changed or not.

        Type handlerClass = getHanderClassType(parent.getSobjectType());
        CRLP_VRollupHandler handler = (CRLP_VRollupHandler) handlerClass.newInstance();

        if (UserInfo.isMultiCurrencyOrganization()) {
            handler.setCurrencyCode((String)parent.get('CurrencyIsoCode'));
        }

        handler.setRecordId(parent.Id);

        // In LDV Mode, pass in the stateful rollups collection.
        if (options.mode == ProcessingMode.LDV && options.rollups != null && options.rollups.size() > 0) {
            handler.setRollupsList(options.rollups);
        }

        handler.processRollups(detailRecords);

        // Save the rollup from the Handler instance into the processing options instance
        options.rollups = handler.rollups;

        return handler.getPopulatedSObject();
    }

    /**
     * @description Called by the same method that calls the startProcessing() method to handle any dml operations
     * and log any dml errors that were generated by the update
     * @param recordsToUpdate List<SObject>
     */
    public static void updateChangedRecordsWithLogging(List<SObject> recordsToUpdate) {
        Map<Id,String> dmlErrors = new Map<Id, String>();

        List<Database.SaveResult> srs = UTIL_DMLService.updateRecords(recordsToUpdate, false);
        for(Integer i=0; i<srs.size(); i++) {
            Database.SaveResult sr = srs[i];
            if (!sr.isSuccess()) {
                Id recordId = recordsToUpdate[i].Id;
                dmlErrors.put(recordId, ERR_ExceptionHandler.beautifyExceptionMessage(sr.getErrors()[0].getMessage()));
            }
        }
        if (!dmlErrors.isEmpty()) {
            logDmlErrors(dmlErrors);
        }
    }

    /**
     * @description Log any captured DML errors to the npsp__Error__c object
     * @param dmlErrors
     * TODO - Refactor this to use what Randi builds in the DML Errors branch
     */
    public static void logDmlErrors(Map<Id, String> dmlErrors) {
        if (dmlErrors != null && dmlErrors.size() > 0) {
            String objTypeName = (new List<Id>(dmlErrors.keySet()))[0].getSobjectType().getDescribe().getName();
            String errMessage = 'The following errors were encountered during updates to the ' + objTypeName + ' records:\n';
            for (Id recordId : dmlErrors.keySet()) {
                errMessage += '\n* ' + recordId + ': ' + dmlErrors.get(recordId);
            }

            // TEMPORARY CODE TO SAVE ALL ERRORS
            Error__c error = new Error__c();
            error.Datetime__c = System.now();
            error.Error_Type__c = 'Rollups DML';
            error.Full_Message__c = errMessage;
            error.Object_Type__c = objTypeName;
            insert error;

        }
    }
}