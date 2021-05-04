module.exports = {
   networks:{
      development:{
         host:"127.0.0.1",
         port:7545,
         network_id:"*"
      }
   },
   compilers:{
      solc:{
         version:"^0.4.0",
         settings:{
            optimizer:{
               enabled:true,
               runs:200
            }
         }
      }
   },
   license:"GPL-3.0"
};