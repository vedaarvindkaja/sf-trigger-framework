Case c = new Case(Subject='Test cancellation', Type='Cancellation', Origin='Phone'); 
insert c; Case saved = [SELECT Resolution__c FROM Case WHERE Id = :c.Id]; 
System.debug('RESOLUTION = ' + saved.Resolution__c);
