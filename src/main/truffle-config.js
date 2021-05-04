module.exports = {
   networks:{
      development:{
         host:"127.0.0.1",
         port:7545,
         network_id:"*",
         gas: 100000000,
         gasPrice: 10000000000,
		   websockets: true
      },
	  test:{
		 host:"https://data-seed-prebsc-1-s1.binance.org",
         port:8545,
         network_id:"97"
	  },
	  live:{
		 host:"https://bsc-dataseed.binance.org/",
         network_id:"56"
	  }
   },
   compilers:{
      solc:{
         version:"^0.8.4",
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