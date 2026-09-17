-- Выручка по каждой позиции с учетом скидки
select product_id,
	unit_price,
	ROUND((unit_price * quantity * (1 - discount))::numeric, 2) as product_revenue
from order_details;

-- Суммарная выручка за месяц по всем позициям
select date_trunc('month', order_date) as month,
	SUM(ROUND((unit_price * quantity * (1 - discount))::numeric, 2)) as total_monthly_revenue
from order_details
left join orders on orders.order_id = order_details.order_id
group by month
order by month;

-- Суммарная выручка за текущий и предыдущий месяцы
select date_trunc('month', order_date) as month,
	SUM(ROUND((unit_price * quantity * (1 - discount))::numeric, 2)) as total_monthly_revenue,
	lag(SUM(ROUND((unit_price * quantity * (1 - discount))::numeric, 2))) OVER(order by date_trunc('month', order_date)) as prev_month_revenue
from order_details
left join orders on orders.order_id = order_details.order_id
group by month
order by month;

-- Абсолютный прирост выручки (в %)
with temporary_table as (
	select
		date_trunc('month', order_date) as month,
		SUM(ROUND((unit_price * quantity * (1 - discount))::numeric, 2)) as total_monthly_revenue
	from order_details
	left join orders on orders.order_id = order_details.order_id
	group by month)
select month,
	total_monthly_revenue,
	lag(total_monthly_revenue) over(order by month) as prev_month_revenue,
	round((total_monthly_revenue - lag(total_monthly_revenue) over(order by month))/lag(total_monthly_revenue) over(order by month) * 100, 2) as revenue_increase
from temporary_table
order by month;

-- ABC-анализ, общая выручка по каждому товару
select
	o.product_id,
	product_name,
	ROUND(SUM(o.unit_price * quantity * (1 - discount))::numeric, 2) as product_revenue from order_details as o
left join products on products.product_id = o.product_id
group by o.product_id, product_name
order by o.product_id;

-- Суммарная выручка по всем товарам
with temporary_table as (
	select
		o.product_id,
		product_name,
		ROUND(SUM(o.unit_price * quantity * (1 - discount))::numeric, 2) as product_revenue
	from order_details as o
	left join products on products.product_id = o.product_id
	group by o.product_id, product_name)
select
	product_id,
	product_name,
	product_revenue,
	SUM(product_revenue) OVER() as total_revenue
from temporary_table
order by product_id;

-- Доля каждого товара в суммарной выручке
with temporary_table as (
	select
		o.product_id,
		product_name,
		ROUND(SUM(o.unit_price * quantity * (1 - discount))::numeric, 2) as product_revenue
	from order_details as o
	left join products on products.product_id = o.product_id
	group by o.product_id, product_name)
select
	product_id,
	product_name,
	product_revenue,
	ROUND((product_revenue/SUM(product_revenue) OVER()) * 100, 2) as prod_rev_share,
	SUM(product_revenue) OVER() as total_revenue
from temporary_table
order by product_id;

-- Накопленная доля
with temporary_table as (
	select
		o.product_id,
		p.product_name,
		ROUND(SUM(o.unit_price * o.quantity * (1 - o.discount))::numeric, 2) as product_revenue
	from order_details as o
		left join products as p on p.product_id = o.product_id
		group by o.product_id, p.product_name),
another_table as (
	select
		product_id,
		product_name,
		ROUND((product_revenue/SUM(product_revenue) OVER()) * 100, 2) as prod_rev_share,
		product_revenue
	from temporary_table)
select
	product_id,
	product_name,
	SUM(prod_rev_share) OVER(order by product_revenue DESC) as cumulative_share
from another_table
order by cumulative_share

-- ABC-анализ, присваивание категорий
with temporary_table as (
	select
		o.product_id,
		p.product_name,
		ROUND(SUM(o.unit_price * o.quantity * (1 - o.discount))::numeric, 2) as product_revenue
	from order_details as o
		left join products as p on p.product_id = o.product_id
		group by o.product_id, p.product_name),
another_table as (
	select
		product_id,
		product_name,
		ROUND((product_revenue/SUM(product_revenue) OVER()) * 100, 2) as prod_rev_share,
		product_revenue
	from temporary_table)
select
	product_id,
	product_name,
	SUM(prod_rev_share) OVER(order by product_revenue DESC) as cumulative_share,
	case
		when SUM(prod_rev_share) OVER(order by product_revenue DESC) <= 80 then 'A'
		when SUM(prod_rev_share) OVER(order by product_revenue DESC) <= 95 then 'B'
		else 'C'
	end as category
from another_table
order by cumulative_share;

-- ABC-нализ по категориям товаров
with temporary_table as (
	select 
		c.category_id,
		c.category_name,
		SUM(od.unit_price * od.quantity * (1 - od.discount)) as revenue
	from categories as c
	left join products as p on c.category_id = p.category_id
	left join order_details as od on p.product_id = od.product_id
	group by c.category_id, c.category_name),
another_table as (
	select 
		category_id,
		category_name,
		revenue,
		SUM(revenue) over () as total_revenue,
		SUM(revenue) over (order by revenue desc) AS cumulative_rev
	from temporary_table),
third_table as (
	select 
		category_id,
		category_name,
		revenue,
		total_revenue,
		cumulative_rev,
		COALESCE(lag(cumulative_rev) over (order by revenue desc), 0) as prev_cumulative_rev
	from another_table)
select 
	category_id,
	category_name,
	ROUND(revenue::numeric, 2) as revenue,
	ROUND((revenue / total_revenue * 100)::numeric, 2) as revenue_share,
	ROUND((cumulative_rev / total_revenue * 100)::numeric, 2) as cumulative_share,
	case 
		when prev_cumulative_rev / total_revenue < 0.80 then 'A'
		when prev_cumulative_rev / total_revenue < 0.95 then 'B'
		else 'C'
	end as abc_category
from third_table
order by revenue desc;

-- RFM-анализ
select MAX(order_date) from orders;

-- RFM-метрики
select
	c.customer_id,
	c.company_name,
	(select max(order_date) from orders) - max(o.order_date) as recency,
	COUNT(distinct o.order_id) as frequency,
	ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric, 2) as monetary
from customers as c
left join orders as o on o.customer_id = c.customer_id
left join order_details as od on od.order_id = o.order_id
group by c.customer_id, c.company_name
order by c.customer_id;

-- Разбиение на ранги
with temporary_table as (
	select 
		c.customer_id,
		c.company_name,
		(select max(order_date) from orders) - max(o.order_date) as recency,
		COUNT(distinct o.order_id) as frequency,
		ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric, 2) as monetary
	from customers as c
	left join orders as o on o.customer_id = c.customer_id
	left join order_details as od on od.order_id = o.order_id
	group by c.customer_id, c.company_name
	order by c.customer_id)
select 
	customer_id, 
	company_name, 
	recency, 
	frequency, 
	monetary,
	NTILE(4) OVER(order by recency DESC) as recency_score,
	NTILE(4) OVER(order by frequency ASC) as frequency_score,
	NTILE(4) OVER(order by monetary ASC) as monetary_score
from temporary_table;

-- Присвоение категорий
with temporary_table as (
	select 
		c.customer_id,
		c.company_name,
		(select max(order_date) from orders) - max(o.order_date) as recency,
		COUNT(distinct o.order_id) as frequency,
		ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric, 2) as monetary
	from customers as c
	left join orders as o on o.customer_id = c.customer_id
	left join order_details as od on od.order_id = o.order_id
	group by c.customer_id, c.company_name
	order by c.customer_id),
another_table as (
	select 
		customer_id, 
		company_name, 
		recency, 
		frequency, 
		monetary,
		NTILE(4) OVER(order by recency DESC) as recency_score,
		NTILE(4) OVER(order by frequency ASC) as frequency_score,
		NTILE(4) OVER(order by monetary ASC) as monetary_score
	from temporary_table)
select 
	customer_id, 
	company_name,
	CONCAT(recency_score, frequency_score, monetary_score) as rfm_customer_score,
	case
		when recency_score >= 3 and frequency_score >= 3 and monetary_score >= 3 then 'VIP'
		when recency_score >= 3 and frequency_score >= 3 then 'Loyal'
		when recency_score >= 3 and frequency_score = 2 then 'Promising'
		when recency_score >= 3 and frequency_score = 1 then 'New'
		when recency_score = 2 and frequency_score >= 2 then 'Needs attention'
		when recency_score = 1 and frequency_score >= 3 and monetary_score >= 3 then 'Cant lose them'
		when recency_score = 1 and frequency_score = 1 and monetary_score = 1 then 'Lost'
		else 'Hibernating'
	end as customer_category
from another_table;

-- Когортный анализ
select distinct
	customer_id,
	DATE_TRUNC('month', MIN(order_date) OVER(partition by customer_id)) as cohort_month
from orders
order by customer_id;

-- Возраст покупок
with temporary_table as (
	select
		customer_id,
		order_id,
		order_date,
		DATE_TRUNC('month', MIN(order_date) OVER(partition by customer_id)) as cohort_month
	from orders)
select
	customer_id,
	order_id,
	order_date,
	cohort_month,
	(EXTRACT(YEAR FROM order_date) - EXTRACT(YEAR FROM cohort_month)) * 12 + (EXTRACT(MONTH FROM order_date) - EXTRACT(MONTH FROM cohort_month)) AS month_number
from temporary_table
order by customer_id, order_date;

-- Размер когорты (сколько клиентов привлекли в определенный месяц)
with temporary_table as (
	select 
		customer_id,
		order_id,
		order_date,
		DATE_TRUNC('month', MIN(order_date) OVER(partition by customer_id)) as cohort_month
	from orders),
another_table as (
	select 
		customer_id,
		order_id,
		order_date,
		cohort_month,
		(EXTRACT(YEAR FROM order_date) - EXTRACT(YEAR FROM cohort_month)) * 12 + (EXTRACT(MONTH FROM order_date) - EXTRACT(MONTH FROM cohort_month)) AS month_number
	from temporary_table)
select 
	cohort_month,
	COUNT(distinct customer_id) as cohort_size
from another_table
where month_number = 0
group by cohort_month;

-- Коэффициент удержания
with customer_orders as (
	select 
		customer_id,
		order_id,
		order_date,
		DATE_TRUNC('month', MIN(order_date) OVER (PARTITION BY customer_id)) as cohort_month,
		DATE_TRUNC('month', order_date) AS order_month,
		(EXTRACT(YEAR FROM order_date) - EXTRACT(YEAR FROM MIN(order_date) OVER (PARTITION BY customer_id))) * 12 + (EXTRACT(MONTH FROM order_date) - EXTRACT(MONTH FROM MIN(order_date) OVER (PARTITION BY customer_id))) as month_number
		from orders),
cohort_size AS (
	select 
		cohort_month,
		COUNT(DISTINCT customer_id) AS total_cohort_customers
	from customer_orders
	where month_number = 0
	group by cohort_month),
retention_raw as (
	select 
		co.cohort_month,
		co.month_number,
		COUNT(distinct co.customer_id) as active_customers
	from customer_orders co
	group by co.cohort_month, co.month_number)
select
	r.cohort_month::date as cohort,
	r.month_number,
	r.active_customers,
	cs.total_cohort_customers,
	ROUND((r.active_customers::numeric / cs.total_cohort_customers) * 100, 2) as retention_pct
from retention_raw r
join cohort_size cs on cs.cohort_month = r.cohort_month
order by cohort, month_number;

-- Расчет суммарной выручки с одного клиента когорты
with order_revenues as (
	select 
		o.customer_id,
		o.order_id,
		o.order_date,
		ROUND((od.unit_price * od.quantity * (1 - od.discount))::numeric, 2) as line_revenue,
		DATE_TRUNC('month', MIN(o.order_date) OVER (PARTITION BY o.customer_id)) as cohort_month,
		(EXTRACT(YEAR FROM o.order_date) - EXTRACT(YEAR FROM MIN(o.order_date) OVER (PARTITION BY o.customer_id))) * 12 + (EXTRACT(MONTH FROM o.order_date) - EXTRACT(MONTH FROM MIN(o.order_date) OVER (PARTITION BY o.customer_id))) AS month_number
	from orders o
	join order_details od on od.order_id = o.order_id),
cohort_size as (
	select 
		cohort_month,
		COUNT(distinct customer_id) as total_customers
	from order_revenues
	where month_number = 0
	group by cohort_month),
monthly_cohort_revenue as (
	select 
		cohort_month,
		month_number,
		SUM(line_revenue) as month_revenue
	from order_revenues
	group by cohort_month, month_number)
select 
	m.cohort_month::date as cohort,
	m.month_number,
	cs.total_customers as cohort_size,
	m.month_revenue,
	SUM(m.month_revenue) over (partition by m.cohort_month order by m.month_number rows between unbounded preceding and current row) as cumulative_revenue,
	ROUND((SUM(m.month_revenue) over (partition by m.cohort_month order by m.month_number rows between unbounded preceding and current row) / cs.total_customers)::numeric, 2) as ltv
from monthly_cohort_revenue m
join cohort_size cs on cs.cohort_month = m.cohort_month
order by cohort, month_number;

-- Анализ замороженного капитала в запасах и риска дефицита
select
	p.product_id,
	p.product_name,
	c.category_name,
	s.company_name,
	p.units_in_stock,
	p.units_on_order,
	p.reorder_level,
	p.unit_price,
	ROUND(p.units_in_stock * p.unit_price::numeric, 2) as stock_value,
	ROUND(p.units_on_order * p.unit_price::numeric, 2) as ordered_value,
	case
		when p.units_in_stock = 0 and p.discontinued = 0 then 'Out of stock'
		when (p.units_in_stock + p.units_on_order) < p.reorder_level and p.discontinued = 0 then 'Reorder needed'
		when p.discontinued = 1 then 'Discontinued'
		else 'OK'
	end as stock_status
from products as p
left join categories as c on c.category_id = p.category_id 
left join suppliers as s on s.supplier_id = p.supplier_id;

-- Анализ замороженного капитала в запасах и риска дефицита по категориям
select 
	c.category_name,
	COUNT(p.product_id) as products_total,
	ROUND(SUM(p.units_in_stock * p.unit_price)::numeric, 2) as category_stock_value,
	COUNT(case 
		when p.discontinued = 0 and (p.units_in_stock + p.units_on_order) < p.reorder_level then 1
	end) as products_to_reorder
from products as p
left join categories as c on c.category_id = p.category_id 
left join suppliers as s on s.supplier_id = p.supplier_id
group by category_name;

-- Анализ эффективности служб доставки
select 
	o.freight,
	o.shipped_date,
	o.required_date,
	s.company_name,
	s.shipper_id,
	case 
		when o.shipped_date > o.required_date and o.shipped_date is not null then 1
		else 0
	end as order_is_late
from orders as o
left join shippers as s on s.shipper_id = o.ship_via
order by order_is_late desc, s.shipper_id;

-- По отдельным перевозчикам, процент просрочек
select
	s.shipper_id,
	s.company_name,
	COUNT(o.order_id) as orders_total,
	COUNT(case
		when o.shipped_date > o.required_date then 1
		end) as total_late_orders,
	COUNT(case when o.shipped_date > o.required_date then 1 end)::numeric / COUNT(o.order_id) * 100 as late_orders_share,
	ROUND(AVG(o.freight)::numeric, 2) avg_freight,
	SUM(o.freight) as transportation_costs
from orders as o
left join shippers as s on s.shipper_id = o.ship_via
group by s.shipper_id, s.company_name;

-- Оценка эффективности персонала
select 
	e.employee_id,
	CONCAT(e.first_name, ' ', e.last_name) as employee,
	COUNT(distinct o.order_id) as emp_orders,
	ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric, 2) as emp_revenue,
	ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric/COUNT(distinct o.order_id), 2) as avg_check
from orders as o 
left join order_details as od on od.order_id = o.order_id 
left join employees as e on e.employee_id = o.employee_id
group by e.employee_id;

-- Эффективвность перонала, средний чек, ранг
with temporary as (
	select 
		e.employee_id,
		CONCAT(e.first_name, ' ', e.last_name) as employee,
		COUNT(distinct o.order_id) as emp_orders,
		ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric, 2) as emp_revenue,
		ROUND(SUM(od.unit_price * od.quantity * (1 - od.discount))::numeric/COUNT(distinct o.order_id), 2) as avg_check
	from orders as o 
	left join order_details as od on od.order_id = o.order_id 
	left join employees as e on e.employee_id = o.employee_id
	group by e.employee_id)
select 
	employee_id,
	employee,
	emp_orders,
	emp_revenue,
	avg_check,
	ROUND(emp_revenue/SUM(emp_revenue) over() * 100 ::numeric, 2) as emp_share,
	RANK() over(order by emp_revenue desc) as emp_rank
from temporary;
