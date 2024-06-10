global interface TimeCommunicationInterface {
    
    // void processTimeCommunications(CommunicationExecution__c execution, Set<Id> recordIds);
    void processTimeCommunications(Set<Id> recordIds);
}
