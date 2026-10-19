-- Base of every manager. On the 3DS runtime the class table itself is the singleton instance.
local C = class("SingletonMonoBehaviour", "MonoBehaviour")
C.__singleton_base = true
function C:Awake() end
function C:CheckInstance() return true end
C.__getters.Instance = function(self) return self end
return C
