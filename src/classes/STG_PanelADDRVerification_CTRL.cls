/*
    Copyright (c) 2014, Salesforce.com Foundation
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Salesforce.com Foundation nor the names of
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
* @author Salesforce.com Foundation
* @date 2014
* @description Controller for the address verification settings page.
 */
public with sharing class STG_PanelADDRVerification_CTRL extends STG_Panel {

    public override String idPanel() { return 'idPanelAddressVerification'; }
    
    public Address_Verification_Settings__c addrVerifSettings { 
        get {
            if(addrVerifSettings == null) addrVerifSettings = UTIL_CustomSettingsFacade.getAddressValidationSettings();
            return addrVerifSettings;
        }
        
        public set; 
    }
    
    public String apiSettingsErrorMessage { get; private set; }
    public String apiSettingsSaveMessage { get; private set; }

    public String apiTestEntry { get; set; }
    public String apiTestResult { get; set; }

    public Boolean skipPreviouslyVerifiedObjects { get; set; } { skipPreviouslyVerifiedObjects = true; } 
    public Boolean nowVerifying { get; private set; } { nowVerifying = false; } 
    public String bulkVerifyMessage { get; set; }

    public override PageReference saveSettings() {
        try {
        	apiTestResult = null;
        	
        	encodeTokenIfNotEncoded(addrVerifSettings);
                        
            Boolean validationError = false;
            apiSettingsErrorMessage = '';
            if(addrVerifSettings.Using_SmartyStreets__c && String.isBlank(addrVerifSettings.Auth_ID__c)) {
                apiSettingsErrorMessage = 'Auth ID cannot be blank. ';
                apiSettingsSaveMessage = null;
                validationError = true;
            }
            
            if(addrVerifSettings.Using_SmartyStreets__c && String.isBlank(addrVerifSettings.Auth_Token__c)) {
                String validationMessage = 'Auth Token cannot be blank.';
                apiSettingsErrorMessage = apiSettingsErrorMessage == null ? validationMessage : apiSettingsErrorMessage + validationMessage; 
                apiSettingsSaveMessage = null;
                validationError = true;
            }
            
            if(!validationError) {
                upsert addrVerifSettings;
                apiSettingsSaveMessage = 'Saved.\n';
                apiSettingsErrorMessage = null;
                return super.saveSettings();
            }
        } catch (Exception e) {
            apiSettingsErrorMessage = 'Did not save settings: ' + e.getMessage();
        }
        return null;
    }
    
    public override PageReference cancelEdit() {
    	apiSettingsErrorMessage = null;
	    apiSettingsSaveMessage = null;
	    apiTestEntry = null;
	    apiTestResult = null;
    	return super.cancelEdit();
    }

    public PageReference testApi() {
        try {
        	encodeTokenIfNotEncoded(addrVerifSettings);
            ADDR_SmartyStreets_Gateway la = new ADDR_SmartyStreets_Gateway(addrVerifSettings);
            ADDR_SmartyStreets_Gateway.ZipResponse sz = la.verifyZip(apiTestEntry);
            apiTestResult = JSON.serializePretty(sz);
        } catch (Exception e) {
        	if(e.getMessage().startsWith('no protocol')) {
        		apiTestResult = 'Please enter endpoint URL';
        	} else if(e.getMessage().startsWith('Unauthorized endpoint')) {
        		apiTestResult = 'Unauthorized endpoint. Please add https://api.smartystreets.com to your list of ' + 
        		                'authorized Remote Sites, under Setup->Security->Remote Site.';
        	} else {
                apiTestResult = e.getMessage();
        	}
        }
        return null;
    }
    
    private void encodeTokenIfNotEncoded(Address_Verification_Settings__c addrVerifSettings) {
    	//SmartyStreets' unencoded token is always 88 chars long
        if(addrVerifSettings.Using_SmartyStreets__c && !String.isBlank(addrVerifSettings.Auth_Token__c) 
        && addrVerifSettings.Auth_Token__c.length() == 88)
            addrVerifSettings.Auth_Token__c = EncodingUtil.urlEncode(addrVerifSettings.Auth_Token__c, 'UTF-8');
    }

    public PageReference bulkVerify() {
    	ADDR_VAlidator_Batch b = new ADDR_VAlidator_Batch(skipPreviouslyVerifiedObjects);
        Database.executeBatch(b); 
        nowVerifying = true;
        bulkVerifyMessage = 'Verifying addresses.';
        return null;
    }
}