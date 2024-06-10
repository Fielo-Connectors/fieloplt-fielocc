global class TimeCommunicationPLT implements TimeCommunicationInterface{

    public static String namespacePrefix {get{
        if (namespacePrefix == null) {
            List<Organization> orgDef = (List<Organization>) Database.query('SELECT NamespacePrefix FROM Organization');
            namespacePrefix = orgDef.isEmpty() ? '' : String.isNotBlank(orgDef.get(0).NamespacePrefix) ? (orgDef.get(0).NamespacePrefix + '__') : '';
        }
        return namespacePrefix;
    } set;}

    // global void processTimeCommunications(CommunicationExecution__c execution, Set<Id> recordIds) {
    global void processTimeCommunications(Set<Id> recordIds) {
        try {
            Set<Id> activeMemberIds = new Set<Id>();
            for (SObject member : Database.query(
                'SELECT Id ' + 
                'FROM FieloPLT__Member__c ' + 
                'WHERE Id IN :recordIds AND ' +
                'FieloPLT__Status__c = \'Active\''
            )) {
                activeMemberIds.add((Id)member.get('Id'));
            }
            recordIds.retainAll(activeMemberIds);

            DateTime now = DateTime.now();
            DateTime startDateTime = DateTime.newInstance(now.year(), now.month(), now.day(), now.hour(), 0, 0);
            DateTime endDateTime = DateTime.newInstance(now.year(), now.month(), now.day(), now.hour(), 59, 59);

            Map<Id, FieloCC__Communication__c> communicationsMap = new Map<Id, FieloCC__Communication__c>(
                (List<FieloCC__Communication__c>) Database.query(
                    'SELECT ' + namespacePrefix + 'Segment__c ' + 
                    'FROM FieloCC__Communication__c ' + 
                    'WHERE FieloCC__CommunicationCampaign__r.FieloCC__Status__c = \'Active\' AND ' + 
                    'FieloCC__Status__c = \'Active\' AND ' +
                    'FieloCC__CommunicationMode__c = \'Scheduled\' AND ' +
                    namespacePrefix + 'Segment__c != null AND ' +
                    '(FieloCC__NextExecutionDateTime__c != null AND ' +
                    'FieloCC__NextExecutionDateTime__c >= :startDateTime AND ' +
                    'FieloCC__NextExecutionDateTime__c <= :endDateTime) AND ' +
                    '((FieloCC__RepetitionMode__c = \'SpecificDate\' AND FieloCC__EndDate__c >= :now) OR ' +
                    '(FieloCC__RepetitionMode__c = \'After\' AND FieloCC__RepetitionCount__c < FieloCC__FrequencyEnds__c))'
                )
            );

            Map<Id, Set<Id>> communicationsBySegment = new Map<Id, Set<Id>>();
            for (FieloCC__Communication__c communication : communicationsMap.values()) {
                Id segmentId = (Id)communication.get(namespacePrefix + 'Segment__c');

                if (communicationsBySegment.containsKey(segmentId)) {
                    communicationsBySegment.get(segmentId).add(communication.Id);
                } else {
                    communicationsBySegment.put(segmentId, new Set<Id>{communication.Id});
                }
            }

            Set<Id> segmentIds = communicationsBySegment.keySet();

            Map<Id, Set<Id>> segmentsByMember = new Map<Id, Set<Id>>();
            for (Id memberId : recordIds) {
                segmentsByMember.put(memberId, segmentIds.clone());
            }

            FieloPLT.SegmentService.verifySegments(segmentsByMember);

            List<FieloCC__CommunicationRequest__c> requestsToInsert = new List<FieloCC__CommunicationRequest__c>();
            for (Id memberId : recordIds) {
                for (Id segmentId : segmentsByMember.get(memberId)) {
                    for (Id communicationId : communicationsBySegment.get(segmentId)) {
                        // TODO: add lookup to execution

                        requestsToInsert.add(
                            new FieloCC__CommunicationRequest__c(
                                FieloCC__Target__c = memberId,
                                FieloCC__Communication__c = communicationId
                            )
                        );
                    }
                }
                // execution.LastTargetProcessed__c = memberId;
            }

            if (!requestsToInsert.isEmpty()) {
                insert requestsToInsert;
            }
        } catch (Exception e) {
            System.debug(
                e.getMessage()  + ' - ' +
                e.getCause()    + ' - ' +
                e.getStackTraceString()
            );
            if (Test.isRunningTest()) throw e;
        }
    }
}