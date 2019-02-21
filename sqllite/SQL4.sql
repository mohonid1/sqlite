WITH RECURSIVE
  transx AS (
     SELECT *, 
	(
		select count(*)
		from order_transactions as b  
		where 
			a.Trans_Date || '-' || a.TxID  >= b.Trans_Date || '-' || b.TxID
			AND a.Fund_Code = b.Fund_Code
	) as seq
	, (
			CASE 
			WHEN [Type] = 'Sell'
			THEN
			0 - Unit
			ELSE
			Unit
			END		
  	) as calc_unit 
	FROM order_transactions as a
  )
  ,outstanding(x, TxID, Fund_Code, seq, calc_unit, os, [status], cost, realize, accu_realize, unrealize) AS (
  	SELECT 1, TxID, Fund_Code, seq, calc_unit
  	, CASE WHEN calc_unit < 0 THEN 0 ELSE calc_unit END 
  	, CASE WHEN calc_unit < 0 THEN 'failed' ELSE 'completed' END as [status]
  	, (CASE WHEN calc_unit < 0 THEN 0 ELSE Amount*1.0 / calc_unit END ) as cost
  	, 0 as realize
  	, 0 as accu_realize
  	, 0 as unrealize
  	from transx WHERE seq = 1
  	UNION ALL 
  	SELECT x+1, s.TxID, s.Fund_Code, s.seq, s.calc_unit
  	, CASE WHEN outstanding.os + s.calc_unit < 0 THEN outstanding.os ELSE outstanding.os + s.calc_unit END as os
  	, CASE WHEN outstanding.os + s.calc_unit < 0 THEN 'failed' ELSE 'completed' END as [status]
  	, 
  	CASE WHEN s.calc_unit < 0 THEN
  		outstanding.cost
  	ELSE
	  	round(
		  	((outstanding.os * outstanding.cost)*1.0 + (s.calc_unit * s.NAV)*1.0) / (outstanding.os + s.calc_unit)
	  	, 4)
  	END as cost
  	, 
  	CASE WHEN s.calc_unit < 0 THEN
  		round(
		  	(s.NAV - outstanding.cost) * s.Unit
	  	, 4)
  	ELSE
	  	0
  	END as realize
  	, 
	CASE WHEN s.calc_unit < 0 THEN
		outstanding.accu_realize + ((s.NAV - outstanding.cost) * s.Unit)
	ELSE
		outstanding.accu_realize
	END as accu_realize
	, 
	round(
	(
		(
		s.NAV - 
		(CASE WHEN s.calc_unit < 0 THEN
	  		outstanding.cost*1.0
	  	ELSE
			((outstanding.os * outstanding.cost)*1.0 + (s.calc_unit * s.NAV)*1.0) / (outstanding.os + s.calc_unit)
	  	END)
	  	) * (CASE WHEN outstanding.os + s.calc_unit < 0 THEN outstanding.os ELSE outstanding.os + s.calc_unit END)
	 ) +
	 (
	 	CASE WHEN s.calc_unit < 0 THEN
			outstanding.accu_realize + ((s.NAV - outstanding.cost) * s.Unit)
		ELSE
			outstanding.accu_realize
		END
	 )
	 , 4)
  	 as unrealize
  	FROM transx as s 
  	INNER JOIN outstanding ON s.Fund_Code = outstanding.Fund_Code WHERE s.seq = x+1
  )
-------------------------------------------------------------------------------------------------------------------------
  select a.Fund_Code, a.TxID as order_from_txid, a.Trans_Date as order_from_date, MIN(a.seq) as [Sequence]
  from transx as a 
  LEFT JOIN outstanding ON a.TxID = outstanding.TxID
  WHERE a.Type = 'Buy' AND outstanding.os > ifnull((
	  select SUM(find_sum_sell.Unit) as sum_sell
	  from transx as find_sum_sell 
	  LEFT JOIN outstanding ON find_sum_sell.TxID = outstanding.TxID
	  WHERE outstanding.[status] = 'completed' 
	  AND find_sum_sell.Type = 'Sell' 
	  AND find_sum_sell.Fund_Code = a.Fund_Code
	  AND find_sum_sell.Trans_Date <= '2019-04-15'
  ), 0)
  AND a.Trans_Date <= '2019-04-15'
  GROUP BY a.Fund_Code
  
--select * from outstanding --WHERE Fund_Code = 'K-FIXED'