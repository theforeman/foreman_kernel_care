import { combineReducers } from 'redux';
import EmptyStateReducer from './Components/EmptyState/EmptyStateReducer';

const reducers = {
  foremanKernelCare: combineReducers({
    emptyState: EmptyStateReducer,
  }),
};

export default reducers;
