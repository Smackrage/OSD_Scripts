select 
FCM.CollectionId, 
C.Name 
from 
dbo.v_R_System r 
join dbo.v_FullCollectionMembership FCM on R.ResourceID = FCM.ResourceID 
join dbo.v_Collection C on C.CollectionID = FCM.CollectionID 
Where 
R.Name0 = 'mhsb3y1s'