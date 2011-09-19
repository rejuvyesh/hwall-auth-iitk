import Network.HTTP.Enumerator
import System.IO
import System.Posix.Unistd (sleep)
import Control.Concurrent (threadDelay)
import Text.Regex
import Data.Maybe
import qualified Data.ByteString.Lazy as B
import Data.ByteString.Lazy.Char8 (unpack)
import Data.ByteString.Char8 (pack)
import Control.Arrow
import System.Environment
import System.Exit
import Control.Exception (finally)
getResponse url = do
                    request <- parseUrl url 
                    withManager $ httpLbs request

isLoggedIn = do 
            res <- getResponse "http://74.125.67.100:80" 
            return $ if statusCode res /= 303 then Left True else Right res 

getMagicString  = matchRegex $ mkRegex "VALUE=\"([0-9a-f]+)\""

getKeepAlive    = matchRegex $ mkRegex "location.href=\"(.+?)\""

getLogout = matchRegex $ mkRegex "href=\"(.+?logout.+?)\"" 

keepAlive str logout = finally first after 
                    where 
                    first = do 
                                putStrLn "Sending Request to keep Alive"
                                resp <- getResponse str
                                threadDelay 200000000   -- Wait 200 seconds
                                keepAlive str logout
                    after = do 
                                status <- logOut logout
                                if status
                                then putStrLn "Logged out successfully"
                                else putStrLn "Cannot logout"

usage   = putStrLn "Version 0.1 beta \nUsage: firewallAuth [-h] username password "
userpass = do 
            putStr "Username: "
            username <- getLine
            putStr "Password: "
            password <- getLine
            return (username,password)
parse ["-h"] = usage   >> exit
parse [] = userpass
parse (a:b:_) = return (a,b)
parse (a:[]) = do  
            putStr "Password: "
            password <- getLine
            return (a,password)
exit    = exitWith ExitSuccess
die     = exitWith (ExitFailure 1)
getAuthenticationInfo = getArgs >>= parse 
alreadyLogged _ =  putStrLn "Already Logged in .. Trying after 60 seconds " >> threadDelay 60000000 >> firewallAuth 

logOut url = do resp <- getResponse url
                return (statusCode resp == 200)

tryToLog (username,password) res = do 
                    putStrLn $ "Hello " ++ username ++ "\nNow trying to login"
                    let authLocation = lookup "Location" (read (show $ responseHeaders res) :: [(String,String)])
                    --print authLocation
                    authRes <- getResponse (fromJust authLocation) -- Connecting to authentication Location 
                    let (magicString:_) = fromJust.getMagicString.unpack $ responseBody authRes
                    --print magicString
                    request <- parseUrl (fromJust authLocation)
                    resp <- withManager.httpLbs $ urlEncodedBody (map (pack *** pack) [("username",username),("password",password),("magic",magicString),("4Tredir","/")]) request 
                    let body = responseBody resp
                    --print body
                    let (logout:_) = (fromJust.getLogout.unpack $ body)
                    putStrLn ("Logout url is "++logout) 
                    --putStrLn $ "Logout Url" ++ (show $ responseHeaders resp)
                    let keepAliveMatch = getKeepAlive $ unpack body
                    case keepAliveMatch of
                        Nothing -> putStrLn "Check Username or password" >> die
                        Just (str:_) -> do 
                                            putStrLn ("Keep Alive URL is "++str)
                                            keepAlive str logout 

firewallAuth = do
                (username,password) <- getAuthenticationInfo   -- Getting Username and password 
                loggedin <- isLoggedIn                         -- Checking If Already Logged in 
                either alreadyLogged (tryToLog (username,password)) loggedin

main = firewallAuth 
