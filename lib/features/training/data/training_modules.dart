import 'package:flutter/material.dart';

import 'training_models.dart';

const trainingModules = <TrainingModule>[
  TrainingModule(
    id: 'quick-start',
    title: 'Quick Start',
    description:
        'Learn how navigation, daily totals, and help access work across the live app.',
    icon: Icons.auto_awesome_outlined,
    steps: [
      TrainingStep(
        id: 'quick-start.intro',
        title: 'Live Training',
        description:
            'This training runs on top of the real app. You can still tap the live controls while the guide is open.',
      ),
      TrainingStep(
        id: 'quick-start.navigation',
        title: 'App Navigation',
        description:
            'Use this navigation area to move between sales, inventory, customer credit, reports, and settings. Your role controls which pages appear.',
        anchorId: 'shell.navigation',
      ),
      TrainingStep(
        id: 'quick-start.dashboard',
        title: 'Daily Snapshot',
        description:
            'The dashboard summarizes revenue, profit, stock health, and recent activity so you can check the business quickly.',
        anchorId: 'dashboard.kpis',
        shellIndex: 5,
      ),
      TrainingStep(
        id: 'quick-start.training',
        title: 'Replay Training Anytime',
        description:
            'Open this training card whenever a staff member needs a refresher or when you want to revisit a workflow.',
        anchorId: 'settings.training',
        shellIndex: 9,
      ),
    ],
  ),
  TrainingModule(
    id: 'pos',
    title: 'POS Checkout',
    description:
        'Walk through product search, filtering, item selection, and cart review on the checkout screen.',
    icon: Icons.shopping_cart_checkout_rounded,
    steps: [
      TrainingStep(
        id: 'pos.search',
        title: 'Search And Scan',
        description:
            'Search by product name or barcode here. On supported devices, the scan button opens the barcode camera for faster checkout.',
        anchorId: 'pos.search',
        shellIndex: 0,
      ),
      TrainingStep(
        id: 'pos.categories',
        title: 'Category Filters',
        description:
            'These chips narrow the product grid so cashiers can jump to a category instead of typing every search.',
        anchorId: 'pos.categories',
      ),
      TrainingStep(
        id: 'pos.products',
        title: 'Live Product Grid',
        description:
            'Each card shows price, stock state, and the selling unit. Tapping a product adds it to the cart immediately.',
        anchorId: 'pos.products',
      ),
      TrainingStep(
        id: 'pos.cart',
        title: 'Cart And Checkout',
        description:
            'Review quantities, discounts, profit, and totals here. On mobile, this same training step highlights the cart action button.',
        anchorId: 'pos.cart',
      ),
    ],
  ),
  TrainingModule(
    id: 'dashboard',
    title: 'Dashboard',
    description:
        'Understand the at-a-glance business view for revenue, stock health, product trends, and recent sales.',
    icon: Icons.space_dashboard_rounded,
    steps: [
      TrainingStep(
        id: 'dashboard.kpis',
        title: 'Key Metrics',
        description:
            'These cards summarize today’s revenue, profit, total sales, product count, and low-stock exposure.',
        anchorId: 'dashboard.kpis',
        shellIndex: 5,
      ),
      TrainingStep(
        id: 'dashboard.insights',
        title: 'Insights Section',
        description:
            'Use this section to spot top sellers, staff performance, or low-stock alerts depending on the user role and available data.',
        anchorId: 'dashboard.insights',
      ),
      TrainingStep(
        id: 'dashboard.recent',
        title: 'Recent Activity',
        description:
            'Recent sales help you confirm that transactions are flowing and let managers review the latest completed receipts.',
        anchorId: 'dashboard.recentSales',
      ),
    ],
  ),
  TrainingModule(
    id: 'products',
    title: 'Products & Inventory',
    description:
        'Manage product records, open the real product form, and understand units, pricing, and stock tracking.',
    icon: Icons.inventory_2_rounded,
    allowedRoles: TrainingRoles.management,
    steps: [
      TrainingStep(
        id: 'products.search',
        title: 'Product Search',
        description:
            'Find items by name, SKU, barcode, or category before editing stock or pricing.',
        anchorId: 'products.search',
        shellIndex: 1,
      ),
      TrainingStep(
        id: 'products.list',
        title: 'Inventory List',
        description:
            'Each row shows stock, price, unit configuration, and quick actions for receiving stock, editing, batch history, or deleting.',
        anchorId: 'products.list',
      ),
      TrainingStep(
        id: 'products.add',
        title: 'Add Product',
        description:
            'This opens the real product form. The next steps move into that screen so you can learn the actual workflow.',
        anchorId: 'products.add',
      ),
      TrainingStep(
        id: 'products.form',
        title: 'Product Details Form',
        description:
            'This section captures the product identity, category, barcode, and optional opening batch expiry for the real product record.',
        anchorId: 'productForm.identity',
        action: TrainingStepAction.openProductForm,
      ),
      TrainingStep(
        id: 'products.units',
        title: 'Units And Conversion',
        description:
            'Use this section when the selling unit is different from the stock unit, like kilograms sold from gram-based stock.',
        anchorId: 'productForm.units',
      ),
      TrainingStep(
        id: 'products.pricing',
        title: 'Pricing And Cost',
        description:
            'Enter selling price, cost type, and review the live margin preview before saving.',
        anchorId: 'productForm.pricing',
      ),
      TrainingStep(
        id: 'products.inventory',
        title: 'Opening Stock',
        description:
            'Set current stock and the low-stock threshold that powers warnings across the app.',
        anchorId: 'productForm.inventory',
      ),
      TrainingStep(
        id: 'products.save',
        title: 'Save The Product',
        description:
            'This button creates the real product. During training you can stop here, or continue and save only when you are ready.',
        anchorId: 'productForm.save',
      ),
    ],
  ),
  TrainingModule(
    id: 'categories',
    title: 'Categories',
    description:
        'Organize products with categories so search, POS filtering, and visual grouping stay clean.',
    icon: Icons.category_rounded,
    allowedRoles: TrainingRoles.management,
    steps: [
      TrainingStep(
        id: 'categories.add',
        title: 'Add Category',
        description:
            'Create a category with a label and color so products can be grouped consistently.',
        anchorId: 'categories.add',
        shellIndex: 2,
      ),
      TrainingStep(
        id: 'categories.list',
        title: 'Category List',
        description:
            'This list shows every category, its icon, color, and edit or delete actions.',
        anchorId: 'categories.list',
      ),
    ],
  ),
  TrainingModule(
    id: 'purchases',
    title: 'Purchases & Suppliers',
    description:
        'Track supplier invoices, stock intake, and supplier history from the purchasing workspace.',
    icon: Icons.local_shipping_rounded,
    allowedRoles: TrainingRoles.management,
    steps: [
      TrainingStep(
        id: 'purchases.tabs',
        title: 'Purchases And Suppliers',
        description:
            'Switch between purchase invoices and supplier records with these tabs.',
        anchorId: 'purchases.tabs',
        shellIndex: 3,
      ),
      TrainingStep(
        id: 'purchases.stats',
        title: 'Purchase Stats',
        description:
            'Review invoice count, supplier count, and total spend for the current database.',
        anchorId: 'purchases.stats',
      ),
      TrainingStep(
        id: 'purchases.new',
        title: 'Create Purchase',
        description:
            'Use this button to record a supplier invoice and receive stock into inventory with cost tracking.',
        anchorId: 'purchases.new',
      ),
      TrainingStep(
        id: 'purchases.list',
        title: 'Invoice History',
        description:
            'Open any invoice here to review supplier details, stock lines, totals, and batch expiry information.',
        anchorId: 'purchases.list',
      ),
    ],
  ),
  TrainingModule(
    id: 'sales',
    title: 'Sales History',
    description:
        'Review completed sales, filter by time, and open receipt details for printing or returns.',
    icon: Icons.receipt_long_rounded,
    steps: [
      TrainingStep(
        id: 'sales.filters',
        title: 'Sales Filters',
        description:
            'These summary cards and filters help you focus on today, this week, this month, or the full history.',
        anchorId: 'sales.filters',
        shellIndex: 4,
      ),
      TrainingStep(
        id: 'sales.list',
        title: 'Sale Records',
        description:
            'Open a sale row to inspect the receipt, see customer or cashier details, print again, or process returns when your role allows it.',
        anchorId: 'sales.list',
      ),
    ],
  ),
  TrainingModule(
    id: 'kopesha',
    title: 'Kopesha Credit',
    description:
        'Manage customer credit accounts, monitor risk, and record repayments.',
    icon: Icons.account_balance_wallet_rounded,
    steps: [
      TrainingStep(
        id: 'kopesha.search',
        title: 'Find Credit Customers',
        description:
            'Search by customer name, phone, or email and narrow the list with due-today, overdue, or risky filters.',
        anchorId: 'kopesha.search',
        shellIndex: 6,
      ),
      TrainingStep(
        id: 'kopesha.stats',
        title: 'Risk Snapshot',
        description:
            'These stats show outstanding balances, due-today accounts, overdue customers, and the highest-risk debtors.',
        anchorId: 'kopesha.stats',
      ),
      TrainingStep(
        id: 'kopesha.list',
        title: 'Customer Credit List',
        description:
            'Every card shows contact details, balance, risk state, and quick actions to open statements or record payments.',
        anchorId: 'kopesha.list',
      ),
      TrainingStep(
        id: 'kopesha.create',
        title: 'Create Customer Account',
        description:
            'Open the live customer-account form here before taking Kopesha sales for someone new.',
        anchorId: 'kopesha.createAccount',
      ),
      TrainingStep(
        id: 'kopesha.form',
        title: 'Customer Account Form',
        description:
            'Capture the customer name and any contact details you want linked to future credit sales and reminders.',
        anchorId: 'customerAccount.form',
        action: TrainingStepAction.openCustomerAccount,
      ),
      TrainingStep(
        id: 'kopesha.save',
        title: 'Save Customer Account',
        description:
            'Saving creates the real account that can be reused from POS and Kopesha statements.',
        anchorId: 'customerAccount.save',
      ),
    ],
  ),
  TrainingModule(
    id: 'profit-loss',
    title: 'Profit & Loss',
    description:
        'Read profit trends, expense categories, and expense history from the finance view.',
    icon: Icons.insert_chart_rounded,
    allowedRoles: TrainingRoles.management,
    steps: [
      TrainingStep(
        id: 'pl.filters',
        title: 'Period Filters',
        description:
            'Switch between 7, 14, 30, and 90 days to compare short-term and longer-term performance.',
        anchorId: 'pl.filters',
        shellIndex: 7,
      ),
      TrainingStep(
        id: 'pl.summary',
        title: 'Profit Summary',
        description:
            'These cards combine revenue, inventory cost, operating expenses, and net profit into a single snapshot.',
        anchorId: 'pl.summary',
      ),
      TrainingStep(
        id: 'pl.addExpense',
        title: 'Record Expense',
        description:
            'Use this action to add operating expenses and keep net profit accurate.',
        anchorId: 'pl.addExpense',
      ),
      TrainingStep(
        id: 'pl.expenses',
        title: 'Expense History',
        description:
            'Recent expenses and category totals help you audit where money is going over time.',
        anchorId: 'pl.expenses',
      ),
    ],
  ),
  TrainingModule(
    id: 'reports',
    title: 'Reports & Insights',
    description:
        'Use cashier, product, debtor, and stock-movement reports for deeper operational analysis.',
    icon: Icons.analytics_rounded,
    allowedRoles: TrainingRoles.management,
    steps: [
      TrainingStep(
        id: 'reports.tabs',
        title: 'Report Tabs',
        description:
            'Switch between cashier summary, top products, debtors, aging, and stock movement reports from here.',
        anchorId: 'reports.tabs',
        shellIndex: 8,
      ),
      TrainingStep(
        id: 'reports.body',
        title: 'Interactive Report Views',
        description:
            'Each tab has its own filters and tables so you can inspect performance, overdue balances, and inventory movement.',
        anchorId: 'reports.body',
      ),
    ],
  ),
  TrainingModule(
    id: 'settings',
    title: 'Settings & Access',
    description:
        'Manage your account, replay training, and review operational controls such as sync, team, and backup.',
    icon: Icons.settings_rounded,
    steps: [
      TrainingStep(
        id: 'settings.training',
        title: 'Training Hub',
        description:
            'Use this section to replay tours, onboard new staff, or reset training progress for the current user.',
        anchorId: 'settings.training',
        shellIndex: 9,
      ),
      TrainingStep(
        id: 'settings.account',
        title: 'My Account',
        description:
            'Manage the current login, change password, or sign out from this account card.',
        anchorId: 'settings.account',
      ),
      TrainingStep(
        id: 'settings.team',
        title: 'Team Access',
        description:
            'Admins can create staff accounts and adjust role permissions from here.',
        anchorId: 'settings.team',
        allowedRoles: {TrainingRoles.admin},
      ),
      TrainingStep(
        id: 'settings.sync',
        title: 'Cloud Sync',
        description:
            'Managers and admins can review sync status, backend settings, and manual sync controls in this section.',
        anchorId: 'settings.sync',
        allowedRoles: TrainingRoles.management,
      ),
      TrainingStep(
        id: 'settings.backup',
        title: 'Backup And Restore',
        description:
            'Use backups before major changes so the shop can recover data quickly if needed.',
        anchorId: 'settings.backup',
        allowedRoles: TrainingRoles.management,
      ),
    ],
  ),
];

const fullTrainingOrder = <String>[
  'quick-start',
  'pos',
  'dashboard',
  'products',
  'categories',
  'purchases',
  'sales',
  'kopesha',
  'profit-loss',
  'reports',
  'settings',
];

List<TrainingModule> availableTrainingModules(String role) => trainingModules
    .where(
      (module) =>
          module.isVisibleFor(role) && module.stepCountForRole(role) > 0,
    )
    .toList(growable: false);
